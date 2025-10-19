local accounting_addon = {
	name = "Accounting",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local itemTaskTypes = {}
--- Item Task Type IDs'
--> AAC 9 = harvested wild potato
local ITEM_TASK_ID_FARMED = 9
--> AAC 10 = looted from monsters 
local ITEM_TASK_ID_LOOTED_FROM_MONSTER = 10
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

local yourPaystubWindow 
local accountingWindow

local currentSession

local latestMoneyChangeStr = "0"
local latestMoneyChange = 0

local sessionSaveTimer = 0
local SESSION_SAVE_TIME = 60000

local pageSize = 20 --> number of sessions on page
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

local function displayOverlayTimeString(timeInSeconds)
    timeInMs = tonumber(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60  
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24
    
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
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

local function addMoneyStrToSessionField(moneyStr, fieldName)
    if currentSession == nil then return end 
    if moneyStr == nil or moneyStr == "" then return end 
    if fieldName == nil or fieldName == "" then return end 

    local currentValue = currentSession[fieldName]
    if currentValue == nil or currentValue == "" then 
        currentValue = "0"
    end 
    local newValue = X2Util:StrNumericAdd(currentValue, moneyStr)
    currentSession[fieldName] = newValue
end 

local function getCleanedItemId(itemId)
    -- Remove the first and last characters of the Item ID string
    if string.sub(itemId, 1, 1) == "[" and string.sub(itemId, -1) == "]" then
        return string.sub(itemId, 2, #itemId - 1)
    end
    return itemId
end 

local function recordPlayerMoneyEvent(change, changeStr, itemTaskType, tradeOtherName)
    latestMoneyChangeStr = changeStr
    latestMoneyChange = change
    if change > 0 then 
        addMoneyStrToSessionField(changeStr, "goldEarned")
    elseif change < 0 then
        addMoneyStrToSessionField(changeStr, "goldSpent") 
    end 
    -- api.Log:Info("PLAYER_MONEY")
end 

local function recordMailboxMoneyTakenEvent()
    if latestMoneyChange > 0 then 
        addMoneyStrToSessionField(latestMoneyChangeStr, "goldMailEarned")
    end
    -- api.Log:Info("MAIL_INBOX_MONEY_TAKEN")
end 
local function recordAuctionBiddenEvent(itemName, moneyStr)
    -- api.Log:Info("AUCTION_BIDDEN")
end
local function recordAuctionBoughtEvent(itemName, moneyStr)
    -- api.Log:Info("AUCTION_BOUGHT_BY_SOMEONE")
end
local function recordAddedItemEvent(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    -- api.Log:Info("ADDED_ITEM")
    -- api.Log:Info("Item Link Text: " .. tostring(itemLinkText))
end

local function formatStringAsGold(moneyStr)
    local endStr = tostring(moneyStr)
    -- format the string in data.profit as last two digies are copper, next two are silver, rest is gold
    local copper = string.sub(endStr, -2)
    local silver = string.sub(endStr, -4, -3)
    local gold = string.sub(endStr, 1, -5)
    if gold == "" then gold = "0" end
    if silver == "" then silver = "0" end
    if copper == "" then copper = "0" end
    endStr = gold .. "g " .. silver .. "s " .. copper .. "c"        
    return endStr
end


local function laborPointsChanged(diff, laborPoints)
    -- If labor is spent, start the labor used timer for accurate kill tracking
    if diff < 0 then 
        laborUsedTimer = 0
        laborUsed = true
    end
    
    if diff < 0 and currentSession ~= nil then 
        currentSession["laborSpent"] = currentSession["laborSpent"] + (diff*-1)
    end 
end

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end
local function getKeysSortedByValue(tbl, sortFunction)
    local keys = {}
    for key in pairs(tbl) do
      table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
      return sortFunction(tbl[a], tbl[b])
    end)
    return keys
end

local function cleanBadSessions(sessions)
    for key, session in pairs(sessions) do 
        if session["endTimestamp"] == nil or session["goldEnd"] == nil then 
            sessions[key] = nil
        end 
    end
end

local function getSessionCount(sessions)
    local sessionCount = 0
    for _ in pairs(sessions) do
        sessionCount = sessionCount + 1
    end
    return sessionCount
end


local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = 1
    if pageIndex > 1 then 
        startingIndex = ((pageIndex - 1) * pageSize) + 1 
    end
    endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()

    if pastSessions == nil then return end
    cleanBadSessions(pastSessions["sessions"])

    local sortedDateKeys = getKeysSortedByValue(pastSessions["sessions"], function(a, b) return tonumber(a.endTimestamp) > tonumber(b.endTimestamp) end)
    -- api.Log:Info(sortedDateKeys)
    local sortedSessions = {}
    for key, value in pairs(sortedDateKeys) do 
        -- api.Log:Info("Key: " .. tostring(key) .. " Value: " .. tostring(value))
        table.insert(sortedSessions, pastSessions["sessions"][value])
    end
    
    

    local count = 1
    for _, sessionObject in ipairs(sortedSessions) do 
        if count >= startingIndex and count < endingIndex then 
            local itemData = {
                -- Sessions data fields
                localTimestamp = sessionObject.localTimestamp,
                endTimestamp = sessionObject.endTimestamp,
                goldStart = sessionObject.goldStart,
                goldStartBank = sessionObject.goldStartBank,
                goldEnd = sessionObject.goldEnd,
                goldEndBank = sessionObject.goldEndBank,
                goldSpent = sessionObject.goldSpent,
                goldEarned = sessionObject.goldEarned,
                goldAHEarned = sessionObject.goldAHEarned,
                goldAHSpent = sessionObject.goldAHSpent,
                goldTradeEarned = sessionObject.goldTradeEarned,
                goldTradeSpent = sessionObject.goldTradeSpent,
                goldMailEarned = sessionObject.goldMailEarned,
                goldMailSpent = sessionObject.goldMailSpent,
                goldFishEarned = sessionObject.goldFishEarned,
                goldFishSpent = sessionObject.goldFishSpent,
                goldShopEarned = sessionObject.goldOtherEarned,
                goldShopSpent = sessionObject.goldOtherSpent,
                index = count,

                -- Required fields
                isViewData = true, 
                isAbstention = false
            }
            -- api.Log:Info(itemData.items)
            itemScrollList:InsertData(count, 1, itemData)
        end
        count = count + 1
    end
    
    if #sortedSessions > 0 then
        local oldestSession = sortedSessions[math.min(#sortedSessions, 30)]
        local newestSession = sortedSessions[1]
        local profit = X2Util:StrNumericSub(newestSession.goldEnd, oldestSession.goldEnd)
        local totalProfitStr = formatStringAsGold(profit)
        accountingWindow.past30daysStr:SetText("Past 30 Days Profit/Loss: " .. totalProfitStr)
    else
        accountingWindow.past30daysStr:SetText("Past 30 Days Profit/Loss: 0g 0s 0c")
    end

end

local function getCurrentPlayerMoney()
    return tostring(X2Util:GetMyMoneyString())
end 


local function saveCurrentSessionToFile()
    if pastSessions == nil then 
        pastSessions = {}
        pastSessions["sessions"] = {}
    end 

    pastSessions["sessions"][currentSession.dateKey] = currentSession

    
    -- api.Log:Info(pastSessions)
    api.File:Write(pastSessionsFilename, pastSessions)
    -- Refresh accounting session list
    local sessionScrollList = accountingWindow.sessionScrollList
    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            local sessionCount = getSessionCount(pastSessions["sessions"])
            maxPage = math.ceil(sessionCount / pageSize)    
        else
            maxPage = 1
        end   
    else
        maxPage = 1
    end 
    sessionScrollList.pageControl.maxPage = maxPage
    fillSessionTableData(sessionScrollList, 1)
    sessionScrollList.pageControl:SetCurrentPage(1, true)
end 

local function endAccountingSession()
    if currentSession == nil then return end 
    -- api.Log:Info("[Your Paystub] Ending accounting session")
    currentSession["endTimestamp"] = api.Time:GetLocalTime()
    currentSession["goldEnd"] = getCurrentPlayerMoney()
    currentSession["goldEndBank"] = nil --> api.Bank:GetCurrency()
    saveCurrentSessionToFile()
    currentSession = nil
    sessionSaveTimer = 0
end

local function startAccountingSession()
    -- api.Log:Info("[Your Paystub] Starting accounting session")
    sessionToStart = {}
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    local date = api.Time:TimeToDate(sessionToStart["localTimestamp"])
    local dateKey = string.format("date%02d%02d%04d", date.month, date.day, date.year)
    sessionToStart["dateKey"] = dateKey
    sessionToStart["goldStart"] = getCurrentPlayerMoney() --> TODO: api.Bag:GetCurrency()
    sessionToStart["goldStartBank"] = nil --> TODO: api.Bag:GetCurrency()
    sessionToStart["goldSpent"] = "0"
    sessionToStart["goldEarned"] = "0"
    sessionToStart["goldAHEarned"] = "0"
    sessionToStart["goldAHSpent"] = "0" 
    sessionToStart["goldTradeEarned"] = "0"
    sessionToStart["goldTradeSpent"] = "0"
    sessionToStart["goldMailEarned"] = "0"
    sessionToStart["goldMailSpent"] = "0"
    sessionToStart["goldFishEarned"] = "0"
    sessionToStart["goldFishSpent"] = "0"
    sessionToStart["goldOtherEarned"] = "0"
    sessionToStart["goldOtherSpent"] = "0"
    -- api.Log:Info(api.Bank:GetCurrency())
    -- Before overwriting the old session, if it isn't null, then let's save it.
    endAccountingSession()

    if pastSessions ~= nil and pastSessions["sessions"] ~= nil and pastSessions["sessions"][dateKey] ~= nil then 
        -- api.Log:Info("[Your Paystub] Overwriting previous session for today.")
        sessionToStart = pastSessions["sessions"][dateKey]
    end

    currentSession = sessionToStart
end 


--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        local date = api.Time:TimeToDate(data["localTimestamp"])
        local dateStr = string.format("%02d/%02d/%04d", date.month, date.day, date.year)
        local titleStr = dateStr .. ": "
        data.profit = X2Util:StrNumericSub(data.goldEnd, data.goldStart)
        -- format the string in data.profit as last two digies are copper, next two are silver, rest is gold
        local profitStr = formatStringAsGold(data.profit)
        local endStr = formatStringAsGold(data.goldEnd)   

        titleStr = titleStr .. " " .. endStr .. " (Profit: " .. profitStr .. ")"

        if string.find(data.profit, "-") then
            subItem.bg:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 0.4) -- Red
        else
            subItem.bg:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 0.4) -- Green
        end


        subItem.sessionTitle:SetText(titleStr)
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
    subItem:SetExtent(580, 35)
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
    sessionTitle:SetText("Unknown Date")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    
    -- Interact Layer overtop of everything
    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    function clickOverlay:OnClick()
        api.Log:Info("Ding!")
    end 
    clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
end

local function OnUpdate(dt)
    -- Every 60 seconds, save the current session to file
    if currentSession ~= nil then 
        sessionSaveTimer = sessionSaveTimer + dt
        if sessionSaveTimer >= SESSION_SAVE_TIME then 
            sessionSaveTimer = 0
            startAccountingSession()
        end 
    end
end 

local function OnLoad()
    -- Initializing addon-wide variables
    local settings = api.GetSettings("your_paystub")
    pastSessionsFilename = "your_paystub_accounting_sessions.lua"
    AH_PRICES = require("your_paystub/data/auction_house_prices")
    -- Initialize the addon's empty window
    yourPaystubWindow = api.Interface:CreateEmptyWindow("yourPaystubWindow", "UIParent")

    -- Load previous sessions, or make empty file.
    pastSessions = api.File:Read(pastSessionsFilename)
    


    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            local sessionCount = getSessionCount(pastSessions["sessions"])
            maxPage = math.ceil(sessionCount / pageSize)    
        else
            maxPage = 1
        end   
    else
        pastSessions = {}
        pastSessions["sessions"] = {}
        api.File:Write(pastSessionsFilename, pastSessions)
        maxPage = 1
    end 

    function yourPaystubWindow:OnEvent(event, ...)
        if event == "PLAYER_MONEY" then      
            recordPlayerMoneyEvent(unpack(arg))
        end
        if event == "MAIL_INBOX_MONEY_TAKEN" then 
            recordMailboxMoneyTakenEvent(unpack(arg))
        end
        if event == "AUCTION_BIDDEN" then 
            recordAuctionBiddenEvent(unpack(arg))
        end
        if event == "AUCTION_BOUGHT_BY_SOMEONE" then 
            recordAuctionBoughtEvent(unpack(arg))
        end
        if event == "ADDED_ITEM" then 
            recordAddedItemEvent(unpack(arg))
        end 

        if event == "CHAT_JOINED_CHANNEL" then 
            updateLastKnownChannel(unpack(arg))
        end 
    end
    yourPaystubWindow:SetHandler("OnEvent", yourPaystubWindow.OnEvent)
    yourPaystubWindow:RegisterEvent("PLAYER_MONEY")
    yourPaystubWindow:RegisterEvent("MAIL_INBOX_MONEY_TAKEN")
    -- yourPaystubWindow:RegisterEvent("AUCTION_BIDDEN")
    -- yourPaystubWindow:RegisterEvent("AUCTION_BOUGHT_BY_SOMEONE")
    yourPaystubWindow:RegisterEvent("ADDED_ITEM")

    yourPaystubWindow:RegisterEvent("CHAT_JOINED_CHANNEL")

    -- paystubDisplayWindow:Show(false)
    accountingWindow = paystubDisplayWindow.tab.window[5].accountingWindow

    
    local sessionScrollList = accountingWindow.sessionScrollList
    sessionScrollList:InsertColumn("", 600, 1, SessionSetFunc, nil, nil, SessionsColumnLayoutSetFunc)
    sessionScrollList:InsertRows(16, false)
    sessionScrollList.listCtrl:DisuseSorting()
    sessionScrollList.pageControl.maxPage = maxPage
    
    sessionScrollList.pageControl:SetCurrentPage(1, true)
    function sessionScrollList:OnPageChangedProc(pageIndex)
        sessionScrollList:DeleteAllDatas()
        sessionScrollList:ResetScroll(0)
        fillSessionTableData(sessionScrollList, pageIndex)
    end 

    -- Add past 30 days profit/loss
    local past30daysStr = accountingWindow:CreateChildWidget("label", "past30daysStr", 0, true)
    past30daysStr.style:SetFontSize(FONT_SIZE.LARGE)
    past30daysStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(past30daysStr, FONT_COLOR.DEFAULT)
    past30daysStr:SetText("Past 30 Days Profit/Loss: ")
    past30daysStr:AddAnchor("BOTTOMLEFT", accountingWindow, 15, 50)
    past30daysStr:SetAutoResize(true)
    accountingWindow.past30daysStr = past30daysStr

    fillSessionTableData(sessionScrollList, 1)
    startAccountingSession()

    api.On("UPDATE", OnUpdate)
    api.SaveSettings()
end

local function OnUnload()
    local settings = api.GetSettings("your_paystub")
    endAccountingSession()
    api.Interface:Free(yourPaystubWindow)
    api.On("UPDATE", function() return end)
    yourPaystubWindow = nil
    accountingWindow:Show(false)
    api.Interface:Free(accountingWindow)
    accountingWindow = nil
    api.SaveSettings()
end

accounting_addon.OnLoad = OnLoad
accounting_addon.OnUnload = OnUnload

return accounting_addon
