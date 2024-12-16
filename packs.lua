
local your_packs_addon = {
	name = "Packs",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local itemTaskTypes = {}
--- Item Task Type IDs
--> AAC 16 = Placed pack into vehicle trade slot
local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
--> AAC 23 = Picked pack up off floor or out of vehicle
local ITEM_TASK_ID_PICKED_PACK_UP = 23
--> AAC 27 = Crafted a pack OR items consumed from pack craft
local ITEM_TASK_ID_PACK_WAS_CRAFTED = 27
--> AAC 39 = Drank a potion
local ITEM_TASK_ID_CONSUMABLE_USED = 39
--> AAC 46 = Mailed item OR take item out of mail
local ITEM_TASK_ID_MAIL_SEND_OR_RECEIVE = 46
--> AAC 61 = Dropped pack on the floor
local ITEM_TASK_ID_PACK_DROPPED = 61
--> AAC 109 = turned pack in DOMESTICALLY
local ITEM_TASK_ID_PACK_TURNED_IN = 109

local AH_PRICES

local packs_helper

local yourPaystubWindow 

local currentBackSlotItem
local lastKnownZone
local currentZone

local lastSeenPrice
local lastSeenCoinType

local currentSession
local pastSessions
local pastSessionsFilename

local sessionTimeoutCounter = 0
local SESSION_TIMEOUT_MS = 60000 * 3  --> 1 minute is 60000
local SESSION_TIMEOUT_MS = 1000 * 15  --> TEST OVERRIDE

local PACK_TIMER_8HRS_IN_SECS = 28800

local pageSize = 10 --> number of sessions on page
local maxPage

-- helpers 
function split(s, sep)
    local fields = {}
    
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    
    return fields
end
local function ConvertColor(color)
    return color / 255
end 


local function differenceBetweenTimestamps(time1, time2)
    local time1Prefix = string.sub(time1, 1, 2)
    local time1Suffix = string.sub(time1, (#time1 - 2) * -1)

    local time2Prefix = string.sub(time2, 1, 2) 
    local time2Suffix = string.sub(time2, (#time2 - 2) * -1)
    local timeDiff = tonumber(time1Suffix) - tonumber(time2Suffix)
    return timeDiff
end 
local function displayTimeString(timeInSeconds)
    timeInMs = tonumber(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60  
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24
    
    return string.format("%02dh %02dm", hours, minutes)
end

local function updateLastKnownChannel(channelId, channelName)
    local targetChannelId = 1
    if channelId ~= 1 then 
      return 
    end 
    if currentZone ~= nil then 
      lastKnownZone = currentZone
    end 
    currentZone = channelName
    -- api.Log:Info("  you have switched zones: " .. tostring(currentZone) .. " from zone: " .. tostring(lastKnownZone))
end 

local function saveCurrentSessionToFile()
    if pastSessions == nil then 
        pastSessions = {}
        pastSessions["sessions"] = {}
    end 

    local coinTypeId = currentSession["coinTypeId"]
    -- Let's fill in the AH prices
    if coinTypeId == 0 then --> Gold
        currentSession["profitTotal"] = currentSession["refundTotal"] / 10000
    elseif coinTypeId == 32103 or coinTypeId == 32106 then --> Charcoal Stabilizers & Dragon Essence Stabilizers
        local stabilizerPrice = AH_PRICES[coinTypeId].average
        currentSession["profitTotal"] = stabilizerPrice * currentSession["refundTotal"]
    elseif coinTypeId == 23633 then --> Gilda Star, valued as Gilda Dust
        local gildaDustPrice = AH_PRICES[8000026].average
        currentSession["profitTotal"] = gildaDustPrice * currentSession["refundTotal"]
    elseif coinTypeId == 40229 then --> Lord's Pence, valued as Lord's Coin
        local lordsCoinPrice = AH_PRICES[26880].average
        currentSession["profitTotal"] = lordsCoinPrice * (currentSession["refundTotal"] / 100)
    else --> Unknown/untradeable/unpriceable 
        currentSession["profitTotal"] = "Unknown"
    end 
    -- TODO: Fill in pack costs
    currentSession["costTotal"] = "Unknown"

    -- Insert it into the top position (to sort by most recent)
    table.insert(pastSessions["sessions"], 1, currentSession)
    api.File:Write(pastSessionsFilename, pastSessions)
end 

local function startPackTurnInSession(packId, coinTypeId)
    sessionToStart = {}
    sessionToStart["packId"] = packId
    sessionToStart["coinTypeId"] = coinTypeId
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    sessionToStart["turnInZone"] = currentZone
    sessionToStart["packCount"] = 0
    sessionToStart["refundTotal"] = 0
    sessionToStart["profitTotal"] = "Unknown"
    sessionToStart["costTotal"] = "Unknown"
    -- TODO: Add date

    -- Before overwriting the old session, if it isn't null, then let's save it.
    if currentSession ~= nil then 
        saveCurrentSessionToFile()
    end 

    currentSession = sessionToStart
end 

local function addPackToSession(refund, coinTypeId, packId) 
    if coinTypeId == currentSession["coinTypeId"] and packId == currentSession["packId"] then 
        currentSession["packCount"] = currentSession["packCount"] + 1
        currentSession["refundTotal"] = currentSession["refundTotal"] + refund
        -- Also, reset the timestamp to latest turn in
        currentSession["localTimestamp"] = api.Time:GetLocalTime()
        -- We need to update the current session timeout as well.
        sessionTimeoutCounter = 0
    end 
end 

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end 

local function recordPackPayment(itemLinkText, itemCount, removeState, itemTaskType, tradeOtherName)
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    if removedItemId == currentBackSlotItem and itemTaskType == ITEM_TASK_ID_PACK_DROPPED then 
        currentBackSlotItem = nil
    end 
    -- api.Log:Info(tostring(currentBackSlotItem) .. " tasktype: " .. tostring(itemTaskType) .. " removestate: " .. tostring(removeState) .. " " .. tostring(tradeOtherName)) 
end
  
local function recordPackPickedUp(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)

    --- Legacy code, please do not touch.
    if packs_helper:IsASpecialtyPackById(tonumber(itemId)) == true then
        currentBackSlotItem = itemId
        if currentBackSlotItem ~= nil and packs_helper:GetSpecialtyPackNameById(tonumber(currentBackSlotItem)) ~= nil then 
            packOriginId = packs_helper:GetSpecialtyPackZoneIdById(tonumber(itemId))
            api.Store:GetSpecialtyRatioBetween(packOriginId, 8)
        end
    end 
    --- Ends untouchable legacy code, PLEASE DO NOT TOUCH.

    -- api.Log:Info("Pack picked up: " .. tostring(currentBackSlotItem) .. ", task id: " .. tostring(itemTaskType))
    -- api.Log:Info(tostring(currentBackSlotItem) .. " tasktype: " .. tostring(itemTaskType) .. " trade name: " .. tostring(tradeOtherName))
end 

local function soldASpecialty(text)
    -- We just sold a pack!
    if currentBackSlotItem ~= nil then 
        -- if there is no session, start one
        if currentSession == nil then 
            startPackTurnInSession(currentBackSlotItem, lastSeenCoinType)
            addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
        else
            local timeRightNow = api.Time:GetLocalTime()
            local timeDelta = tonumber(timeRightNow) - tonumber(currentSession["localTimestamp"])
            -- api.Log:Info(tostring(timeDelta))
            -- if there is a session, see if it's been less than 5 minutes. if it has been, write to current session
            -- NOTE: start a new session if the turned in pack doesnt match the packId or its cointype ID
            if lastSeenCoinType == currentSession["coinTypeId"] and currentBackSlotItem == currentSession["packId"] then
                addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
            elseif lastSeenCoinType ~= currentSession["coinTypeId"] or currentBackSlotItem ~= currentSession["packId"] then
                startPackTurnInSession(currentBackSlotItem, lastSeenCoinType)
                addPackToSession(lastSeenPrice, lastSeenCoinType, currentBackSlotItem)
            end 
        end 
        
    end 

    currentBackSlotItem = nil
end 

local function soldAtResourceTrader(text)
    -- api.Log:Info("sold: " .. text)
end

local function getSpecialtyInfo(specialtyRatioTable)
    for key, value in pairs(specialtyRatioTable) do 
        -- api.Log:Info(value.itemInfo.name .. " at " .. value.ratio .. "%")
    end 
end 

local function traderDialogOpened(refund, itemType, itemGrade, coinType)
    -- api.Log:Info(tostring(itemType) .. " turns in for " .. tostring(refund) .. " of coinType: " .. tostring(coinType))
    lastSeenPrice = refund
    lastSeenCoinType = coinType
end

local function OnUpdate(dt) 
    if sessionTimeoutCounter + dt > SESSION_TIMEOUT_MS then
        -- Save, and clear session
        if currentSession ~= nil then 
            api.Log:Err("Ending current pack session...")
            saveCurrentSessionToFile()
            currentSession = nil
            
        end 
        sessionTimeoutCounter = 0
    end 
    sessionTimeoutCounter = sessionTimeoutCounter + dt
end 

--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        -- Data Assignments
        local sessionIndex = data.index
        local packObject = packs_helper:GetSpecialtyPackNameById(tonumber(data.packId))
        local packName = packObject.name or nil
        local turnInZone = data.turnInZone
        local packCount = tostring(data.packCount)
        local coinTypeId = tonumber(data.coinTypeId)
        local profitTotal = data.profitTotal
        local costTotal = data.costTotal
        local coinTypeName = "Unknown refund type"
        if coinTypeId ~= nil then 
            coinTypeName = api.Item:GetItemInfoByType(coinTypeId).name
        end
        local timeDiffTilNow = PACK_TIMER_8HRS_IN_SECS - differenceBetweenTimestamps(api.Time:GetLocalTime(), data.localTimestamp)
        local timeDiffStr = "Payment In: " .. displayTimeString(tonumber(timeDiffTilNow))
        -- Display Strings
        local leftTextStr = packName .. " x" .. packCount 
        if coinTypeId == 0 then 
            leftTextStr = leftTextStr .. "\n " .. string.format('%.2f', tostring(data.refundTotal / 10000)) .. " Gold"
        elseif coinTypeId > 0 then
            leftTextStr = leftTextStr .. "\n " .. coinTypeName .. " x" .. tostring(data.refundTotal)
        end

        local rightTextStr = "Profit: " .. tostring(profitTotal)
        if type(profitTotal) == "number" then 
            rightTextStr = "Profit: " .. string.format('%.2f', tostring(profitTotal)) .. "g"
        end 
        if type(costTotal) == "number" then 
            rightTextStr = rightTextStr .. " \n " .. "Cost: " .. string.format('%.2f', tostring(costTotal)) .. "g"
        else 
            rightTextStr = rightTextStr .. " \n " .. "Cost: " .. tostring(costTotal)
        end 
        
        
        local titleStr = "Unknown Zone Specialty Turn-in"
        if turnInZone ~= nil then 
            titleStr = turnInZone .. " Specialty Turn-in"
            if coinTypeId == 0 then 
                titleStr = titleStr .. " (Domestic)"
            elseif coinTypeId > 0 then 
                titleStr = titleStr .. " (International)"
            end 
        end 
        
        subItem.id = id
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        if timeDiffTilNow > 0 then 
            -- Not paid yet, set background to red and paid label to remaining time
            subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
            subItem.sessionIsPaidLabel:SetText(timeDiffStr)
        else
            -- Has been paid, set background to green.
            subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
            subItem.sessionIsPaidLabel:SetText("Paid out")
        end 
        -- F_SLOT.SetIconBackGround(subItem.subItemIcon, data.dds)
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)

    -- local session1PackAmt = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackAmt.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackAmt, FONT_COLOR.DEFAULT)
    -- session1PackAmt:SetText("Karkasse Aged Cheese x13 (1831.09g)")
    -- session1PackAmt:AddAnchor("TOPLEFT", session1, 50, 40)
    -- session1PackAmt:SetAutoResize(true)
    -- session1PackAmt.style:SetAlign(ALIGN.LEFT)
    -- local session1PackLabor = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackLabor.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackLabor, FONT_COLOR.DEFAULT)
    -- session1PackLabor:SetText("Labor: 2028")
    -- session1PackLabor:AddAnchor("TOPRIGHT", session1, 0, 20)
    -- session1PackLabor:SetAutoResize(true)
    -- session1PackLabor.style:SetAlign(ALIGN.RIGHT)
    -- local session1PackPay = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackPay.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackPay, FONT_COLOR.DEFAULT)
    -- session1PackPay:SetText("Total: 1831.09g")
    -- session1PackPay:AddAnchor("TOPRIGHT", session1, 0, 40)
    -- session1PackPay:SetAutoResize(true)
    -- session1PackPay.style:SetAlign(ALIGN.RIGHT)
    -- local session1PackProfit = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackProfit.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackProfit, FONT_COLOR.DEFAULT)
    -- session1PackProfit:SetText("Profit: 1509.79g")
    -- session1PackProfit:AddAnchor("TOPRIGHT", session1, 0, 60)
    -- session1PackProfit:SetAutoResize(true)
    -- session1PackProfit.style:SetAlign(ALIGN.RIGHT)
    subItem:SetExtent(580, 70)
    -- Background colouring
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    bg:Show(true)
    subItem.bg = bg
    -- Top-left Session Title
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Turn-in")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    -- Pack Item Icon 
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)

    -- Top-right Session "Is paid?" Label
    local sessionIsPaidLabel = subItem:CreateChildWidget("label", "sessionIsPaidLabel", 0, true)
    sessionIsPaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionIsPaidLabel, FONT_COLOR.DEFAULT)
    sessionIsPaidLabel:SetText("")
    sessionIsPaidLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionIsPaidLabel:SetAutoResize(true)
    sessionIsPaidLabel.style:SetAlign(ALIGN.RIGHT)

    -- Left-side Text
    local textboxLeft = subItem:CreateChildWidget("textbox", "textboxLeft", 0, true)
    textboxLeft:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxLeft:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    textboxLeft.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(textboxLeft, FONT_COLOR.DEFAULT)
    subItem.textboxLeft = textboxLeft
    -- Right-side Text
    local textboxRight = subItem:CreateChildWidget("textbox", "textboxRight", 0, true)
    textboxRight:AddAnchor("TOPLEFT", subItem, 55, 10)
    textboxRight:AddAnchor("BOTTOMRIGHT", subItem, -12, 0)
    textboxRight.style:SetAlign(ALIGN.RIGHT)
    ApplyTextColor(textboxRight, FONT_COLOR.DEFAULT)
    subItem.textboxRight = textboxRight
    -- Interact Layer overtop of everything
    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    function clickOverlay:OnClick()
        -- modelViewerEquipItem(subItem.id, nil, dressUpWindow.modelViewer)
        api.Log:Info("Ding!")
    end 
    clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
end

local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = 1
    if pageIndex > 1 then 
        startingIndex = ((pageIndex - 1) * pageSize) + 1 
    end
    endingIndex = startingIndex + pageSize
    
    local count = 1
    for _, sessionObject in pairs(pastSessions["sessions"]) do 
        if count >= startingIndex and count < endingIndex then 
            local itemData = {
                -- localTimestamp = "1733471130",
                -- packId = "42023",
                -- refundTotal = 482872,
                -- packCount = 1,
                -- coinTypeId = 0,
                -- Sessions data fields
                localTimestamp = sessionObject.localTimestamp,
                packId = sessionObject.packId,
                refundTotal = sessionObject.refundTotal,
                profitTotal = sessionObject.profitTotal,
                costTotal = sessionObject.costTotal,
                packCount = sessionObject.packCount, 
                coinTypeId = sessionObject.coinTypeId,
                turnInZone = sessionObject.turnInZone,
                
                index = count,

                -- Required fields
                isViewData = true, 
                isAbstention = false
            }
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end 
end
---

local function OnLoad()
    packs_helper = require("your_paystub/packs_helper")
    AH_PRICES = require("your_paystub/data/auction_house_prices")
    -- Initialize the addon's empty window
    yourPaystubWindow = api.Interface:CreateEmptyWindow("yourPaystubWindow", "UIParent")
    
    -- Initializing addon-level variables
    currentBackSlotItem = nil
    lastKnownZone = nil
    currentZone = nil
    currentSession = nil
    lastSeenPrice = nil
    lastSeenCoinType = nil
    pastSessionsFilename = "your_paystub/pack_sessions/sessions.lua"

    -- Load past sessions
    pastSessions = api.File:Read(pastSessionsFilename)
    maxPage = math.ceil(#pastSessions.sessions / pageSize)

    for packId, pack in pairs(packs_helper.packsInfo) do
        local packZoneId = 0
        for zoneId, zoneName in pairs(packs_helper.zonesInfo) do
            if string.find(pack.name, zoneName) then 
                packZoneId = zoneId
            end 
        end 
        -- api.Log:Info("  This pack belongs to zone: " .. packZoneId)
        
        pack.destinations = {}
        if packZoneId ~= 0 then
            local sellableZones = api.Store:GetSellableZoneGroups(packZoneId)
            for key, value in pairs(sellableZones) do
                for key, value in pairs(value) do 
                    -- api.Log:Info(key .. " " .. tostring(value))
                end         
                pack.destinations[tostring(key)] = {} 
                pack.destinations[tostring(key)].id = tostring(value.id)
                pack.destinations[tostring(key)].name = tostring(value.name)
            end
        end 
        -- api.Log:Info(table.concat(pack.destinations, ","))
        pack.zone = packZoneId
        
    end 
    

    -- local exampleSession = api.File:Read("your_paystub/pack_sessions/1733267924.lua")
    -- api.Log:Info(exampleSession)
    -- local currentTime = api.Time:GetLocalTime()
    -- local currentTimePrefix = string.sub(currentTime, 1, 2)
    -- local currentTimeSuffix = string.sub(currentTime, (#currentTime - 2) * -1)

    -- local exampleTimePrefix = string.sub(exampleSession.localTimestamp, 1, 2) 
    -- local exampleTimeSuffix = string.sub(exampleSession.localTimestamp, (#exampleSession.localTimestamp - 2) * -1)

    -- api.Log:Info("Times: prefix/suffix " .. currentTimePrefix .. currentTimeSuffix .. " vs. " .. exampleTimePrefix .. exampleTimeSuffix)
    -- local timeDiff = tonumber(currentTimeSuffix) - tonumber(exampleTimeSuffix)
    -- api.Log:Info(tostring(timeDiff))

    local productionZones = api.Store:GetProductionZoneGroups()
    function yourPaystubWindow:OnEvent(event, ...)
        if event == "REMOVED_ITEM" then      
            recordPackPayment(unpack(arg))
        end
        if event == "ADDED_ITEM" then
            recordPackPickedUp(unpack(arg))
        end 
        if event == "SELL_SPECIALTY" then 
            soldASpecialty(unpack(arg))
        end
        if event == "STORE_SELL" then
            soldAtResourceTrader(unpack(arg))
        end
        if event == "SPECIALTY_RATIO_BETWEEN_INFO" then 
            getSpecialtyInfo(unpack(arg))
        end 
        if event == "CHAT_JOINED_CHANNEL" then 
            updateLastKnownChannel(unpack(arg))
        end 
        -- if event == "ADDED_ITEM" then 
        --     -- api.Log:Info("heya")
        --     trackLoot(unpack(arg))
        -- end 
        if event == "UPDATE_SPECIALTY_RATIO" then 
            traderDialogOpened(unpack(arg))
        end 
    end

    yourPaystubWindow:SetHandler("OnEvent", yourPaystubWindow.OnEvent)
    yourPaystubWindow:RegisterEvent("ADDED_ITEM")
    yourPaystubWindow:RegisterEvent("REMOVED_ITEM")
    yourPaystubWindow:RegisterEvent("STORE_SELL")
    yourPaystubWindow:RegisterEvent("SELL_SPECIALTY")
    yourPaystubWindow:RegisterEvent("SPECIALTY_RATIO_BETWEEN_INFO")
    yourPaystubWindow:RegisterEvent("CHAT_JOINED_CHANNEL")
    yourPaystubWindow:RegisterEvent("ITEM_ACQUISITION_BY_LOOT")
    yourPaystubWindow:RegisterEvent("UPDATE_SPECIALTY_RATIO")
    yourPaystubWindow:RegisterEvent("SELL_SPECIALTY_CONTENT_INFO")

    -- Initializing Commerce Tab
    paystubDisplayWindow:Show(false)
    commerceWindow = paystubDisplayWindow.tab.window[1].commerceWindow
    local sessionScrollList = commerceWindow.sessionScrollList
    sessionScrollList:InsertColumn("", 600, 1, SessionSetFunc, nil, nil, SessionsColumnLayoutSetFunc)
    sessionScrollList:InsertRows(8, false)
    sessionScrollList.listCtrl:DisuseSorting()
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, 1)
    sessionScrollList.pageControl:SetCurrentPage(1, true)
    function sessionScrollList:OnPageChangedProc(pageIndex)
        sessionScrollList:DeleteAllDatas()
        sessionScrollList:ResetScroll(0)
        fillSessionTableData(sessionScrollList, pageIndex)
    end 

    -- local sellableZones = api.Store:GetSellableZoneGroups(99)
    -- for key, value in pairs(sellableZones) do
    --     api.Log:Info("Zone: " .. key .. ", Value: " .. value.name)
    -- end
    
    

    -- local currentDate = api.Time:TimeToDate(api.Time.GetLocalTime())

    -- api.Log:Info(api.Time:GetGameTime())

    
    
    -- api.Map:ToggleMapWithPortal(323, 16461, 11630, 100)
    -- api.Log:Info(tostring(currentDate.year) .. "-" .. tostring(currentDate.month) .. "-" .. tostring(currentDate.day))

    api.On("UPDATE", OnUpdate)
    -- api.SaveSettings()
end

local function OnUnload()
    yourPaystubWindow:ReleaseHandler("OnEvent")
    api.On("UPDATE", function() return end)
    yourPaystubWindow = nil
end

your_packs_addon.OnLoad = OnLoad
your_packs_addon.OnUnload = OnUnload

return your_packs_addon