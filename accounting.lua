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
local accountingUIInitialized = false

local currentSession

local latestMoneyChangeStr = "0"
local latestMoneyChange = 0

local sessionSaveTimer = 0
local SESSION_SAVE_TIME = 180000
local sessionDirty = false

-- Rolling time window tracking (persisted to disk)
local totalEarnedNum = 0
local totalSpentNum = 0

local minuteEarned = {}
local minuteSpent = {}
local minuteHead = 0
local minuteCount = 0

local hourEarned = {}
local hourSpent = {}
local hourHead = 0
local hourCount = 0

local minuteSnapshotTimer = 0
local MINUTE_SNAPSHOT_TIME = 60000
local hourSnapshotTimer = 0
local HOUR_SNAPSHOT_TIME = 3600000

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
local function differenceBetweenTimestamps(time1, time2)
    local time1Prefix = string.sub(time1, 1, 2)
    local time1Suffix = string.sub(time1, (#time1 - 2) * -1)

    local time2Prefix = string.sub(time2, 1, 2) 
    local time2Suffix = string.sub(time2, (#time2 - 2) * -1)
    local timeDiff = tonumber(time1Suffix) - tonumber(time2Suffix)
    return timeDiff
end 
local function displayTimeString(timeInSeconds)
    local timeInMs = tonumber(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24

    return string.format("%02dh %02dm", hours, minutes)
end

local function displayOverlayTimeString(timeInSeconds)
    local timeInMs = tonumber(timeInSeconds)
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
        totalEarnedNum = totalEarnedNum + change
        sessionDirty = true
    elseif change < 0 then
        addMoneyStrToSessionField(changeStr, "goldSpent")
        totalSpentNum = totalSpentNum + (-change)
        sessionDirty = true
    end
end

local function recordMailboxMoneyTakenEvent()
    if latestMoneyChange > 0 then
        addMoneyStrToSessionField(latestMoneyChangeStr, "goldMailEarned")
        sessionDirty = true
    end
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


local function formatGoldShort(num)
    local val = math.floor(math.abs(num))
    local gold = math.floor(val / 10000)
    local silver = math.floor((val % 10000) / 100)
    return string.format("%d.%02dg", gold, silver)
end

local function getTimeWindowValues(earnedBuf, spentBuf, head, count, bufSize, slotsBack)
    if count == 0 then return nil, nil end
    local actualBack = math.min(slotsBack, count - 1)
    local idx = ((head - actualBack - 1) % bufSize) + 1
    return totalEarnedNum - earnedBuf[idx], totalSpentNum - spentBuf[idx]
end

local function updateTimeWindowLabels()
    if accountingWindow == nil then return end
    local windows = {
        {earnedBuf = minuteEarned, spentBuf = minuteSpent, head = minuteHead, count = minuteCount, bufSize = 60, slotsBack = 15, label = "15m"},
        {earnedBuf = minuteEarned, spentBuf = minuteSpent, head = minuteHead, count = minuteCount, bufSize = 60, slotsBack = 60, label = "1h"},
        {earnedBuf = hourEarned, spentBuf = hourSpent, head = hourHead, count = hourCount, bufSize = 24, slotsBack = 5, label = "5h"},
        {earnedBuf = hourEarned, spentBuf = hourSpent, head = hourHead, count = hourCount, bufSize = 24, slotsBack = 12, label = "12h"},
    }
    for i, w in ipairs(windows) do
        local earned, spent = getTimeWindowValues(w.earnedBuf, w.spentBuf, w.head, w.count, w.bufSize, w.slotsBack)
        local earnedLabel = accountingWindow["twEarned" .. i]
        local spentLabel = accountingWindow["twSpent" .. i]
        if earnedLabel and spentLabel then
            if earned then
                earnedLabel:SetText(w.label .. "  ▲ " .. formatGoldShort(earned))
                spentLabel:SetText("▼ " .. formatGoldShort(spent))
            else
                earnedLabel:SetText(w.label .. "  ▲ ...")
                spentLabel:SetText("▼ ...")
            end
        end
    end
end

local function laborPointsChanged(diff, laborPoints)
    -- If labor is spent, start the labor used timer for accurate kill tracking
    if diff < 0 then 
        laborUsedTimer = 0
        laborUsed = true
    end
    
    if diff < 0 and currentSession ~= nil then
        currentSession["laborSpent"] = currentSession["laborSpent"] + (diff*-1)
        sessionDirty = true
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
    local endingIndex = startingIndex + pageSize
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


local function refreshAccountingUI()
    if not accountingUIInitialized then return end
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

local function saveCurrentSessionToFile()
    if pastSessions == nil then
        pastSessions = {}
        pastSessions["sessions"] = {}
    end

    pastSessions["sessions"][currentSession.dateKey] = currentSession

    pastSessions["timeWindows"] = {
        totalEarnedNum = totalEarnedNum,
        totalSpentNum = totalSpentNum,
        minuteEarned = minuteEarned,
        minuteSpent = minuteSpent,
        minuteHead = minuteHead,
        minuteCount = minuteCount,
        hourEarned = hourEarned,
        hourSpent = hourSpent,
        hourHead = hourHead,
        hourCount = hourCount,
    }

    api.File:Write(pastSessionsFilename, pastSessions)

    if paystubDisplayWindow ~= nil and paystubDisplayWindow:IsVisible() then
        refreshAccountingUI()
    end
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
    local sessionToStart = {}
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
        local profitNum = tonumber(data.profit) or 0
        local sign = profitNum < 0 and "-" or ""
        local profitStr = sign .. formatGoldShort(profitNum)
        local endStr = formatStringAsGold(data.goldEnd)

        local earned = tonumber(data.goldEarned or "0") or 0
        local spent = tonumber(data.goldSpent or "0") or 0
        titleStr = titleStr .. " " .. endStr .. " (Profit: " .. profitStr .. ")"

        if profitNum < 0 then
            subItem.bg:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 0.4) -- Red
        else
            subItem.bg:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 0.4) -- Green
        end

        subItem.sessionTitle:SetText(titleStr)
        subItem.earnedLabel:SetText("▲ " .. formatGoldShort(earned))
        subItem.spentLabel:SetText("▼ " .. formatGoldShort(spent))
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

    -- Earned label (green ▲) same row, after title
    local earnedLabel = subItem:CreateChildWidget("label", "earnedLabel", 0, true)
    earnedLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    earnedLabel.style:SetAlign(ALIGN.LEFT)
    earnedLabel.style:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 1)
    earnedLabel:SetText("")
    earnedLabel:AddAnchor("LEFT", sessionTitle, 370, 0)
    earnedLabel:SetAutoResize(true)
    subItem.earnedLabel = earnedLabel

    -- Spent label (red ▼) same row, after earned
    local spentLabel = subItem:CreateChildWidget("label", "spentLabel", 0, true)
    spentLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    spentLabel.style:SetAlign(ALIGN.LEFT)
    spentLabel.style:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 1)
    spentLabel:SetText("")
    spentLabel:AddAnchor("LEFT", earnedLabel, 100, 0)
    spentLabel:SetAutoResize(true)
    subItem.spentLabel = spentLabel

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
    if currentSession ~= nil then
        sessionSaveTimer = sessionSaveTimer + dt
        if sessionSaveTimer >= SESSION_SAVE_TIME then
            sessionSaveTimer = 0
            if sessionDirty then
                sessionDirty = false
                currentSession["endTimestamp"] = api.Time:GetLocalTime()
                currentSession["goldEnd"] = getCurrentPlayerMoney()
                currentSession["goldEndBank"] = nil
                if pastSessions == nil then
                    pastSessions = {}
                    pastSessions["sessions"] = {}
                end
                pastSessions["sessions"][currentSession.dateKey] = currentSession
                pastSessions["timeWindows"] = {
                    totalEarnedNum = totalEarnedNum,
                    totalSpentNum = totalSpentNum,
                    minuteEarned = minuteEarned,
                    minuteSpent = minuteSpent,
                    minuteHead = minuteHead,
                    minuteCount = minuteCount,
                    hourEarned = hourEarned,
                    hourSpent = hourSpent,
                    hourHead = hourHead,
                    hourCount = hourCount,
                }
                api.File:Write(pastSessionsFilename, pastSessions)
                if accountingUIInitialized and paystubDisplayWindow ~= nil and paystubDisplayWindow:IsVisible() then
                    refreshAccountingUI()
                end
            end
        end
    end

    -- Minute snapshots for 15m/1h windows
    minuteSnapshotTimer = minuteSnapshotTimer + dt
    if minuteSnapshotTimer >= MINUTE_SNAPSHOT_TIME then
        minuteSnapshotTimer = 0
        minuteHead = (minuteHead % 60) + 1
        minuteEarned[minuteHead] = totalEarnedNum
        minuteSpent[minuteHead] = totalSpentNum
        if minuteCount < 60 then minuteCount = minuteCount + 1 end
    end

    -- Hour snapshots for 12h/24h windows
    hourSnapshotTimer = hourSnapshotTimer + dt
    if hourSnapshotTimer >= HOUR_SNAPSHOT_TIME then
        hourSnapshotTimer = 0
        hourHead = (hourHead % 24) + 1
        hourEarned[hourHead] = totalEarnedNum
        hourSpent[hourHead] = totalSpentNum
        if hourCount < 24 then hourCount = hourCount + 1 end
    end
end

local function initAccountingUI()
    if accountingUIInitialized then return end
    accountingUIInitialized = true

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

    local past30daysStr = accountingWindow:CreateChildWidget("label", "past30daysStr", 0, true)
    past30daysStr.style:SetFontSize(FONT_SIZE.LARGE)
    past30daysStr.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(past30daysStr, FONT_COLOR.DEFAULT)
    past30daysStr:SetText("Past 30 Days Profit/Loss: ")
    past30daysStr:AddAnchor("BOTTOMLEFT", accountingWindow, 15, 50)
    past30daysStr:SetAutoResize(true)
    accountingWindow.past30daysStr = past30daysStr

    -- Time window labels (15m, 1h on row 1; 5h, 12h on row 2)
    local twLabels = {"15m", "1h", "5h", "12h"}
    local twXOffsets = {15, 310, 15, 310}
    local twYOffsets = {30, 30, 48, 48}
    for i = 1, 4 do
        local earnedLabel = accountingWindow:CreateChildWidget("label", "twEarned" .. i, 0, true)
        earnedLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
        earnedLabel.style:SetAlign(ALIGN.LEFT)
        earnedLabel.style:SetColor(ConvertColor(11), ConvertColor(156), ConvertColor(35), 1)
        earnedLabel:SetText(twLabels[i] .. "  ▲ ...")
        earnedLabel:AddAnchor("TOPLEFT", accountingWindow, twXOffsets[i], twYOffsets[i])
        earnedLabel:SetAutoResize(true)
        accountingWindow["twEarned" .. i] = earnedLabel

        local spentLabel = accountingWindow:CreateChildWidget("label", "twSpent" .. i, 0, true)
        spentLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
        spentLabel.style:SetAlign(ALIGN.LEFT)
        spentLabel.style:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 1)
        spentLabel:SetText("▼ ...")
        spentLabel:AddAnchor("LEFT", earnedLabel, 130, 0)
        spentLabel:SetAutoResize(true)
        accountingWindow["twSpent" .. i] = spentLabel
    end

    fillSessionTableData(sessionScrollList, 1)
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

    -- Restore time window data from disk, or seed fresh (must be before startAccountingSession)
    if pastSessions and pastSessions.timeWindows then
        local tw = pastSessions.timeWindows
        totalEarnedNum = tw.totalEarnedNum or 0
        totalSpentNum = tw.totalSpentNum or 0
        minuteEarned = tw.minuteEarned or {}
        minuteSpent = tw.minuteSpent or {}
        minuteHead = tw.minuteHead or 0
        minuteCount = tw.minuteCount or 0
        hourEarned = tw.hourEarned or {}
        hourSpent = tw.hourSpent or {}
        hourHead = tw.hourHead or 0
        hourCount = tw.hourCount or 0
    else
        minuteHead = 1
        minuteEarned[1] = 0
        minuteSpent[1] = 0
        minuteCount = 1
        hourHead = 1
        hourEarned[1] = 0
        hourSpent[1] = 0
        hourCount = 1
    end

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
    if accountingWindow ~= nil then
        accountingWindow:Show(false)
        api.Interface:Free(accountingWindow)
        accountingWindow = nil
    end
    api.SaveSettings()
end

accounting_addon.OnLoad = OnLoad
accounting_addon.UpdateTimeWindowLabels = updateTimeWindowLabels
accounting_addon.OnUnload = OnUnload
accounting_addon.initUI = initAccountingUI

return accounting_addon
