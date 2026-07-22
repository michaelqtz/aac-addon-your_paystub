
local your_fishing_addon = {
	name = "Fishing",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local fishing_helper
local accountingAddon

--- Item Task Type IDs (shared with packs.lua)
--> AAC 16 = Placed item into vehicle trade slot
local ITEM_TASK_ID_PACK_IN_VEHICLE = 16
--> AAC 61 = Dropped item on the floor
local ITEM_TASK_ID_PACK_DROPPED = 61

local yourPaystubWindow
local fishingWindow

local lastKnownZone
local currentZone

-- Fish sales are matched by pairing a REMOVED_ITEM (the fish leaving the bag)
-- with a PLAYER_MONEY gain that happens around the same time -- confirmed via
-- WriteEventParameters logging that these are the two real events a fish
-- turn-in fires (no specialty trader dialog, no back-slot equip tracking).
local pendingFishId
local pendingFishTimer = 0
local pendingGold
local pendingGoldTimer = 0
local MATCH_WINDOW_MS = 5000

local currentSession
local pastSessions
local pastSessionsFilename

local sessionTimeoutCounter = 0
--> Fish stands are turned in in quick bursts, so use a shorter grouping
--> window than the 3-minute one used for specialty packs.
local SESSION_TIMEOUT_MS = 20000

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000

local pageSize = 20 --> number of sessions on page
local maxPage

-- helpers
local function split(s, sep)
    local fields = {}
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
end
local function ConvertColor(color)
    return color / 255
end

--> Large local-time values can round-trip through file serialization in
--> scientific notation, corrupting the timestamp. Force a plain integer string.
local function getSafeTimestamp()
    local t = api.Time:GetLocalTime()
    return string.format("%.0f", tonumber(t) or 0)
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
end

-- Statistics functions
local function getTotalGoldMadeFromFishing()
    local totalGold = 0
    if pastSessions == nil then return totalGold end
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        if type(sessionObject.profitTotal) == "number" then
            totalGold = totalGold + sessionObject.profitTotal
        end
    end
    return totalGold
end
local function getTotalFishSold()
    local totalFish = 0
    if pastSessions == nil then return totalFish end
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        totalFish = totalFish + (sessionObject.fishCount or 0)
    end
    return totalFish
end
local function getFavouriteFishType()
    local fishCounts = {}
    if pastSessions == nil then return nil end
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        local fishId = sessionObject.fishId
        if fishId ~= nil then
            if fishCounts[fishId] == nil then
                fishCounts[fishId] = 0
            end
            fishCounts[fishId] = fishCounts[fishId] + (sessionObject.fishCount or 0)
        end
    end

    local favouriteFishId = nil
    local maxCount = 0
    for fishId, count in pairs(fishCounts) do
        if count > maxCount then
            maxCount = count
            favouriteFishId = fishId
        end
    end

    return favouriteFishId
end

local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = 1
    if pageIndex > 1 then
        startingIndex = ((pageIndex - 1) * pageSize) + 1
    end
    local endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()

    if pastSessions == nil then return end

    local count = 1
    for _, sessionObject in pairs(pastSessions["sessions"]) do
        if count >= startingIndex and count < endingIndex then
            local itemData = {
                localTimestamp = sessionObject.localTimestamp,
                fishId = sessionObject.fishId,
                refundTotal = sessionObject.refundTotal,
                profitTotal = sessionObject.profitTotal,
                fishCount = sessionObject.fishCount,
                coinTypeId = sessionObject.coinTypeId,
                turnInZone = sessionObject.turnInZone,

                index = count,

                isViewData = true,
                isAbstention = false
            }
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end
end

local function isPaystubWindowOpen()
    if paystubDisplayWindow:IsVisible() then
        return true
    else
        return false
    end
end

local function refreshSessionDisplay()
    local sessionScrollList = fishingWindow.sessionScrollList
    if pastSessions ~= nil and pastSessions.sessions ~= nil then
        maxPage = math.ceil(#pastSessions.sessions / pageSize)
    else
        maxPage = 1
    end
    if maxPage < 1 then maxPage = 1 end
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, sessionScrollList.pageControl:GetCurrentPageIndex() or 1)
end

local function saveCurrentSessionToFile()
    if pastSessions == nil then
        pastSessions = {}
        pastSessions["sessions"] = {}
    end

    if tonumber(currentSession["coinTypeId"]) == 0 then
        currentSession["profitTotal"] = currentSession["refundTotal"] / 10000
    else
        currentSession["profitTotal"] = "Unknown"
    end

    -- Insert it into the top position (to sort by most recent)
    table.insert(pastSessions["sessions"], 1, currentSession)
    api.File:Write(pastSessionsFilename, pastSessions)

    refreshSessionDisplay()
end

local function startFishTurnInSession(fishId, coinTypeId)
    -- Before overwriting the old session, if it isn't null, then let's save it.
    if currentSession ~= nil then
        api.Log:Info("[Your Paystub] Ending fishing session")
        saveCurrentSessionToFile()
    end

    api.Log:Info("[Your Paystub] Starting fishing session")
    currentSession = {
        fishId = fishId,
        coinTypeId = coinTypeId,
        localTimestamp = getSafeTimestamp(),
        turnInZone = currentZone,
        fishCount = 0,
        refundTotal = 0,
        profitTotal = 0
    }
end

local function addFishToSession(refund, coinTypeId, fishId)
    if currentSession == nil then
        startFishTurnInSession(fishId, coinTypeId)
    elseif coinTypeId ~= currentSession["coinTypeId"] or fishId ~= currentSession["fishId"] then
        startFishTurnInSession(fishId, coinTypeId)
    end

    currentSession["fishCount"] = currentSession["fishCount"] + 1
    currentSession["refundTotal"] = currentSession["refundTotal"] + refund
    currentSession["localTimestamp"] = getSafeTimestamp()
    sessionTimeoutCounter = 0
end

-- Pairs a pending fish removal with a pending gold gain, whichever order
-- they arrived in (observed logs show PLAYER_MONEY can fire just before
-- REMOVED_ITEM for the same sale).
local function tryMatchFishSale()
    if pendingFishId ~= nil and pendingGold ~= nil and pendingGold > 0 then
        addFishToSession(pendingGold, 0, pendingFishId)
        if accountingAddon ~= nil and accountingAddon.RecordFishGold ~= nil then
            accountingAddon.RecordFishGold(pendingGold)
        end
        displayRefreshCounter = DISPLAY_REFRESH_MS
        pendingFishId = nil
        pendingGold = nil
    end
end

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end

--- Fired whenever any item leaves the player. We only care about fish leaving
--- for a reason other than being dropped or stowed into a vehicle slot.
local function recordFishPayment(itemLinkText, itemCount, removeState, itemTaskType, tradeOtherName)
    if not itemLinkText then return end
    local removedItemId = tonumber(itemIdFromItemLinkText(itemLinkText))
    if removedItemId == nil or not fishing_helper:IsAFishById(removedItemId) then
        return
    end

    if itemTaskType == ITEM_TASK_ID_PACK_DROPPED or itemTaskType == ITEM_TASK_ID_PACK_IN_VEHICLE then
        return
    end

    pendingFishId = removedItemId
    pendingFishTimer = 0
    tryMatchFishSale()
end

--- Fired on any change to the player's money. A positive amount within a few
--- seconds of a fish leaving the bag is treated as that fish's sale price.
local function handlePlayerMoneyChanged(amount, amount2, moneyType, extra)
    local changeAmount = tonumber(amount) or 0
    if changeAmount <= 0 then return end

    pendingGold = changeAmount
    pendingGoldTimer = 0
    tryMatchFishSale()
end

local function refreshStatisticsLabels()
    local totalGold = getTotalGoldMadeFromFishing()
    local totalFish = getTotalFishSold()
    local favouriteFishId = getFavouriteFishType()

    fishingWindow.totalGoldStr:SetText("Total Gold from Fishing: " .. string.format('%.2f', totalGold) .. "g")
    fishingWindow.totalFishStr:SetText("Total Fish Sold: " .. totalFish)

    local favouriteFishName = "No favourite yet."
    if favouriteFishId ~= nil then
        local itemInfo = api.Item:GetItemInfoByType(tonumber(favouriteFishId))
        if itemInfo ~= nil then
            favouriteFishName = itemInfo.name
        end
    end
    fishingWindow.favouriteFishStr:SetText("Favourite Fish: " .. favouriteFishName)
end

local function OnUpdate(dt)
    if pendingFishId ~= nil then
        pendingFishTimer = pendingFishTimer + dt
        if pendingFishTimer > MATCH_WINDOW_MS then
            pendingFishId = nil
        end
    end
    if pendingGold ~= nil then
        pendingGoldTimer = pendingGoldTimer + dt
        if pendingGoldTimer > MATCH_WINDOW_MS then
            pendingGold = nil
        end
    end

    if currentSession ~= nil then
        if sessionTimeoutCounter + dt > SESSION_TIMEOUT_MS then
            api.Log:Info("[Your Paystub] Ending fishing session")
            saveCurrentSessionToFile()
            currentSession = nil
            sessionTimeoutCounter = 0
        else
            sessionTimeoutCounter = sessionTimeoutCounter + dt
        end
    end

    -- Only refresh the display if the paystub window is open
    if isPaystubWindowOpen() then
        if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then
            displayRefreshCounter = 0
            refreshSessionDisplay()
            refreshStatisticsLabels()
        end
        displayRefreshCounter = displayRefreshCounter + dt
    else
        displayRefreshCounter = DISPLAY_REFRESH_MS
    end
end

--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        local fishInfo = api.Item:GetItemInfoByType(tonumber(data.fishId))
        local fishName = "Unknown Fish (id: " .. tostring(data.fishId) .. ")"
        if fishInfo ~= nil and fishInfo.name ~= nil then
            fishName = fishInfo.name
        end

        local turnInZone = data.turnInZone
        local fishCount = tostring(data.fishCount)
        local coinTypeId = tonumber(data.coinTypeId)
        local profitTotal = data.profitTotal
        local date = api.Time:TimeToDate(tostring(data.localTimestamp))

        -- Display Strings
        local leftTextStr = fishName .. " x" .. fishCount
        if coinTypeId == 0 then
            leftTextStr = leftTextStr .. "\n " .. string.format('%.2f', tostring(data.refundTotal / 10000)) .. " Gold"
        end

        local rightTextStr = "Profit: " .. tostring(profitTotal)
        if type(profitTotal) == "number" then
            rightTextStr = "Profit: " .. string.format('%.2f', tostring(profitTotal)) .. "g"
        end

        if fishInfo ~= nil and fishInfo.path ~= nil then
            F_SLOT.SetIconBackGround(subItem.subItemIcon, fishInfo.path)
        end

        local titleStr = "Unknown Zone Fishing Turn-in"
        if turnInZone ~= nil then
            titleStr = turnInZone .. " Fishing Turn-in"
        end

        subItem.id = data.fishId
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        -- Fish sales pay out instantly, so every session is already settled.
        subItem.bg:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 0.3)
        if date ~= nil then
            subItem.sessionDateLabel:SetText(string.format("%02d/%02d/%04d", date.month, date.day, date.year))
        else
            subItem.sessionDateLabel:SetText("")
        end
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    subItem:SetExtent(580, 70)
    -- Background colouring
    local bg = subItem:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 0.3)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", subItem, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    bg:Show(true)
    subItem.bg = bg
    -- Top-left Session Title
    local sessionTitle = subItem:CreateChildWidget("label", "sessionTitle", 0, true)
    sessionTitle.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionTitle, FONT_COLOR.DEFAULT)
    sessionTitle:SetText("Unknown Fishing Turn-in")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    -- Fish Item Icon
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    -- Top-right Date Label
    local sessionDateLabel = subItem:CreateChildWidget("label", "sessionDateLabel", 0, true)
    sessionDateLabel.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(sessionDateLabel, FONT_COLOR.DEFAULT)
    sessionDateLabel:SetText("")
    sessionDateLabel:AddAnchor("TOPRIGHT", subItem, -12, 10)
    sessionDateLabel:SetAutoResize(true)
    sessionDateLabel.style:SetAlign(ALIGN.RIGHT)

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
end
---

local function OnLoad()
    fishing_helper = require("your_paystub/fishing_helper")
    accountingAddon = require("your_paystub/accounting")

    -- Initializing the addon's empty window
    yourPaystubWindow = api.Interface:CreateEmptyWindow("yourPaystubFishingWindow", "UIParent")
    yourPaystubWindow:Show(true)

    -- Initializing addon-level variables
    lastKnownZone = nil
    currentZone = nil
    currentSession = nil
    pendingFishId = nil
    pendingGold = nil
    pastSessionsFilename = "your_paystub_fishing_sessions.lua"

    -- Load past sessions
    pastSessions = api.File:Read(pastSessionsFilename)
    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            maxPage = math.ceil(#pastSessions.sessions / pageSize)
        else
            maxPage = 1
        end
    else
        pastSessions = {}
        pastSessions["sessions"] = {}
        api.File:Write(pastSessionsFilename, pastSessions)
        maxPage = 1
    end
    if maxPage < 1 then maxPage = 1 end

    -- NOTE: this handler must forward "..." directly -- the legacy "arg"
    -- global is NOT populated by this client for vararg event handlers, so
    -- "unpack(arg)" throws silently and drops the event before it ever
    -- reaches the functions below.
    function yourPaystubWindow:OnEvent(event, ...)
        if event == "REMOVED_ITEM" then
            recordFishPayment(...)
        end
        if event == "PLAYER_MONEY" then
            handlePlayerMoneyChanged(...)
        end
        if event == "CHAT_JOINED_CHANNEL" then
            updateLastKnownChannel(...)
        end
    end

    yourPaystubWindow:SetHandler("OnEvent", yourPaystubWindow.OnEvent)
    yourPaystubWindow:RegisterEvent("REMOVED_ITEM")
    yourPaystubWindow:RegisterEvent("PLAYER_MONEY")
    yourPaystubWindow:RegisterEvent("CHAT_JOINED_CHANNEL")

    -- Load and write statistics to paystub window
    local totalGold = getTotalGoldMadeFromFishing()
    local totalFish = getTotalFishSold()
    local favouriteFishId = getFavouriteFishType()

    -- Initializing Fishing Tab
    fishingWindow = paystubDisplayWindow.tab.window[2].fishingWindow
    local sessionScrollList = fishingWindow.sessionScrollList
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
    fishingWindow.sessionScrollList = sessionScrollList

    local totalGoldStr = fishingWindow:CreateChildWidget("label", "totalGoldStr", 0, true)
    totalGoldStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalGoldStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalGoldStr, FONT_COLOR.DEFAULT)
    totalGoldStr:SetText("Total Gold from Fishing: " .. string.format('%.2f', totalGold) .. "g")
    totalGoldStr:AddAnchor("BOTTOMLEFT", fishingWindow, 15, 50)
    fishingWindow.totalGoldStr = totalGoldStr

    local totalFishStr = fishingWindow:CreateChildWidget("label", "totalFishStr", 0, true)
    totalFishStr.style:SetFontSize(FONT_SIZE.LARGE)
    totalFishStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(totalFishStr, FONT_COLOR.DEFAULT)
    totalFishStr:SetText("Total Fish Sold: " .. totalFish)
    totalFishStr:AddAnchor("BOTTOMLEFT", totalGoldStr, 0, 20)
    fishingWindow.totalFishStr = totalFishStr

    local favouriteFishName = "No favourite yet."
    if favouriteFishId ~= nil then
        local itemInfo = api.Item:GetItemInfoByType(tonumber(favouriteFishId))
        if itemInfo ~= nil then
            favouriteFishName = itemInfo.name
        end
    end
    local favouriteFishStr = fishingWindow:CreateChildWidget("label", "favouriteFishStr", 0, true)
    favouriteFishStr.style:SetFontSize(FONT_SIZE.LARGE)
    favouriteFishStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(favouriteFishStr, FONT_COLOR.DEFAULT)
    favouriteFishStr:SetText("Favourite Fish: " .. favouriteFishName)
    favouriteFishStr:AddAnchor("BOTTOMLEFT", totalFishStr, 0, 20)
    fishingWindow.favouriteFishStr = favouriteFishStr

    api.On("UPDATE", OnUpdate)
end

local function OnUnload()
    if currentSession ~= nil then
        api.Log:Info("[Your Paystub] Ending fishing session")
        saveCurrentSessionToFile()
        currentSession = nil
    end
    api.Interface:Free(yourPaystubWindow)
    api.On("UPDATE", function() return end)
    yourPaystubWindow = nil
end

your_fishing_addon.OnLoad = OnLoad
your_fishing_addon.OnUnload = OnUnload

return your_fishing_addon
