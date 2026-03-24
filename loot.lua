local your_loot_addon = {
	name = "Packs",
	author = "Michaelqt",
	version = "",
	desc = ""
}

local sa = require("your_paystub/session_archive")

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
--> AAC 41 = From dawnsdrop pickaxe
local ITEM_TASK_ID_DAWNSDROP_PICKAXE = 41
--> AAC 46 = Mailed item OR take item out of mail
local ITEM_TASK_ID_MAIL_SEND_OR_RECEIVE = 46
--> AAC 61 = Dropped pack on the floor
local ITEM_TASK_ID_PACK_DROPPED = 61
--> AAC 109 = turned pack in DOMESTICALLY
local ITEM_TASK_ID_PACK_TURNED_IN = 109

local AH_PRICES

local yourPaystubWindow
local lootWindow
local lootSessionDetailsWindow
local lootUIInitialized = false

local lastKnownZone
local currentZone

local currentSession
local pastSessions
local pastSessionsFilename

local laborUsedTimer = 0
local laborUsed = false
local LABOR_USED_TIMER_RATE = 300

local sessionClockRefreshTimer = 0
local SESSION_CLOCK_REFRESH_RATE = 1000
local lootTrackerSessionTimer = 0
local sessionPaused

local displayRefreshCounter = 0
local DISPLAY_REFRESH_MS = 60000
local displayDirty = false

local pageSize = 20 --> number of sessions on page
local maxPage

local archiveFilename = "your_paystub_loot_sessions_archive.lua"

-- Shared helpers (from session_archive)
local split = sa.split
local ConvertColor = sa.ConvertColor
local differenceBetweenTimestamps = sa.differenceBetweenTimestamps
local displayTimeString = sa.displayTimeString

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

local function getCleanedItemId(itemId)
    -- Remove the first and last characters of the Item ID string
    if string.sub(itemId, 1, 1) == "[" and string.sub(itemId, -1) == "]" then
        return string.sub(itemId, 2, #itemId - 1)
    end
    return itemId
end 

local function getSessionByIndex(index)
    return sa.getSessionByIndex(pastSessions, archiveFilename, index)
end

local function fillSessionTableData(itemScrollList, pageIndex)
    local startingIndex = ((pageIndex - 1) * pageSize) + 1
    local endingIndex = startingIndex + pageSize
    itemScrollList:DeleteAllDatas()

    if pastSessions == nil then return end

    local count = 1
    for i = startingIndex, endingIndex - 1 do
        local sessionObject = getSessionByIndex(i)
        if sessionObject == nil then break end
        local itemData = {
            localTimestamp = sessionObject.localTimestamp,
            endTimestamp = sessionObject.endTimestamp,
            items = sessionObject.items,
            profitTotal = sessionObject.profitTotal,
            laborSpent = sessionObject.laborSpent,
            costTotal = sessionObject.costTotal,
            kills = sessionObject.kills,
            zone = sessionObject.zone,
            index = i,

            -- Required fields
            isViewData = true,
            isAbstention = false
        }
        itemScrollList:InsertData(count, 1, itemData)
        count = count + 1
    end
end

local function saveCurrentSessionToFile()
    displayDirty = true
    if pastSessions == nil then
        pastSessions = {}
        pastSessions["sessions"] = {}
    end

    local items = currentSession["items"]
    -- Let's fill in the AH prices
    currentSession["profitTotal"] = 0
    for itemId, itemCount in pairs(items) do 
        -- item IDs are stored in [itemId] format in the current session
        local cleanedItemId = getCleanedItemId(itemId)
        local itemPrice = AH_PRICES[tonumber(cleanedItemId)]
        
        if itemPrice ~= nil then
            if itemPrice.average ~= nil then 
                itemPrice = itemPrice.average
            else 
                itemPrice = 0
            end
        else 
            itemPrice = 0
        end
        currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
    end
    -- TODO: Fill in loot session costs
    currentSession["endTimestamp"] = api.Time:GetLocalTime()
    currentSession["costTotal"] = "Unknown"

    -- Iterate through old sessions and change their item arrays to use [itemId] format
    for _, pastSession in ipairs(pastSessions.sessions) do 
        local oldItems = pastSession.items
        local newItems = {}
        for oldItemId, itemCount in pairs(oldItems) do 
            if string.sub(oldItemId, 1, 1) == "[" and string.sub(oldItemId, -1) == "]" then
                newItems[oldItemId] = itemCount
            else
                newItems["[" .. oldItemId .. "]"] = itemCount
            end
        end 
        pastSession.items = newItems
    end
    -- Insert it into the top position (to sort by most recent)
    table.insert(pastSessions["sessions"], 1, currentSession)

    -- Archive overflow: move oldest sessions to archive file
    sa.archiveOverflow(pastSessions, archiveFilename)

    api.File:Write(pastSessionsFilename, pastSessions)

    -- Refresh loot session list (only if UI is initialized)
    if lootUIInitialized then
        local sessionScrollList = lootWindow.sessionScrollList
        maxPage = sa.refreshPageControl(sessionScrollList, pastSessions, pageSize)
        fillSessionTableData(sessionScrollList, 1)
    end
end

local function endLootTrackerSession()
    if currentSession == nil then return end 
    api.Log:Info("[Your Paystub] Ending loot tracker session")
    saveCurrentSessionToFile()
    currentSession = nil
    lootTrackerSessionTimer = 0
end

local function startLootTrackerSession()
    api.Log:Info("[Your Paystub] Starting loot tracker session")
    local sessionToStart = {}
    sessionToStart["localTimestamp"] = api.Time:GetLocalTime()
    sessionToStart["zone"] = currentZone
    sessionToStart["kills"] = 0
    sessionToStart["laborSpent"] = 0
    sessionToStart["profitTotal"] = 0
    sessionToStart["costTotal"] = 0
    sessionToStart["items"] = {}
    -- TODO: Add date

    -- Before overwriting the old session, if it isn't null, then let's save it.
    endLootTrackerSession()

    currentSession = sessionToStart
end 



local function addItemToSession(itemId, itemCount)
    if currentSession == nil or sessionPaused then return end 
    local cleanItemId = itemId 
    itemId = "[" .. itemId .. "]"
    if currentSession["items"][itemId] == nil then 
        currentSession["items"][itemId] = itemCount
    else 
        currentSession["items"][itemId] = currentSession["items"][itemId] + itemCount
    end 

    -- Add to the display for total profit
    local itemPrice = AH_PRICES[tonumber(cleanItemId)]
    if itemPrice ~= nil then
        itemPrice = itemPrice.average
    else 
        itemPrice = 0
    end
    currentSession["profitTotal"] = currentSession["profitTotal"] + (itemPrice * itemCount)
    displayDirty = true
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

local function trackKill(unitId, expAmount, expString)
    local playerId = api.Unit:GetUnitId("player")
    if playerId == unitId and laborUsed == false then 
        if currentSession ~= nil then 
            currentSession["kills"] = currentSession["kills"] + 1
        end 
    end
end 

local function itemIdFromItemLinkText(itemLinkText)
    local itemIdStr = string.sub(itemLinkText, 3)
    itemIdStr = split(itemIdStr, ",")
    itemIdStr = itemIdStr[1]
    return itemIdStr
end 

local function removedItem(itemLinkText, itemCount, removeState, itemTaskType, tradeOtherName)
    local removedItemId = itemIdFromItemLinkText(itemLinkText)
    local itemInfo = api.Item:GetItemInfoByType(tonumber(removedItemId))
    -- api.Log:Info("Removed: " .. itemInfo.name .. " x" .. itemCount .. " taskType: " .. itemTaskType)
end
  
local function lootedItem(itemLinkText, itemCount, itemTaskType, tradeOtherName)
    local itemId = itemIdFromItemLinkText(itemLinkText)
    if itemTaskType == ITEM_TASK_ID_LOOTED_FROM_MONSTER or itemTaskType == ITEM_TASK_ID_FARMED or itemTaskType == ITEM_TASK_ID_DAWNSDROP_PICKAXE then
        addItemToSession(itemId, itemCount)
    end

    local itemInfo = api.Item:GetItemInfoByType(tonumber(itemId))
    -- api.Log:Info("Looted: " .. itemInfo.name .. " x" .. itemCount .. " taskType: " .. itemTaskType)
end 

local function fillInAHPricesForCrates()
    local CRATE_IDS = {
        42074, -- Noble's Crate
        42075, -- Jester's Crate
        42076, -- Prince's Crate
        42077, -- Queen's Crate
        43177, -- Ancestral Crate
    }
    for _, crateId in ipairs(CRATE_IDS) do 
        local itemInfo = api.Item:GetItemInfoByType(crateId)
        -- Jester's and Noble's
        local sunDustId = 16347
        local moonDustId = 16348
        local starDustId = 16349
        -- Prince's, Queen's and Ancestrals
        local brazierId = 15983
        local treeId = 35301
        local mgpId = 23653 --> Mysterious Garden Powder

        local sunDustPrice = (AH_PRICES[sunDustId] and AH_PRICES[sunDustId].average) or 0
        local moonDustPrice = (AH_PRICES[moonDustId] and AH_PRICES[moonDustId].average) or 0
        local starDustPrice = (AH_PRICES[starDustId] and AH_PRICES[starDustId].average) or 0
        local mgpPrice = (AH_PRICES[mgpId] and AH_PRICES[mgpId].average) or 0

        local brazierPrice = 0.5
        local treePrice = 0.5
        

        -- To Reddit: I literally opened the server's database and looked up these crate drop rates.
        --          Accept it. I have access to things I shouldn't have access to. 
        --          I'm obviously kidding grow up.
        if crateId == 42074 then 
            -- Nobles
            local cratePrice = (sunDustPrice * 1.8) + (moonDustPrice * 1.8) + (starDustPrice * 0.9) + (mgpPrice * 0.18)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42075 then
            -- Jesters 
            local cratePrice = (sunDustPrice * 2.2) + (moonDustPrice * 2.2) + (starDustPrice * 1.1) + (mgpPrice * 0.20)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42076 then
            -- Princes 
            local cratePrice = (brazierPrice * 1) + (treePrice * 1) + (mgpPrice * 0.2)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 42077 then
            -- Queens 
            local cratePrice = (brazierPrice * 2.25) + (treePrice * 2.25) + (mgpPrice * 0.25)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        elseif crateId == 43177 then
            -- Ancestrals
            local cratePrice = (brazierPrice * 5) + (treePrice * 5) + (mgpPrice * 0.8)
            AH_PRICES[crateId] = {}
            AH_PRICES[crateId].average = cratePrice
        end 
    end
end 

local function fillInRegradeBrazierPrices()
    local REGRADE_BRAZIER_LOOT_IDS = {}
    REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"] = 31085
    REGRADE_BRAZIER_LOOT_IDS["Starpoint"] = 31929
    REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"] = 28304
    REGRADE_BRAZIER_LOOT_IDS["Moonpoint"] = 28302
    REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"] = 28303
    REGRADE_BRAZIER_LOOT_IDS["Sunpoint"] = 28301
    REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"] = 39816
    REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"] = 31930
    REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"] = 39815
    REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"] = 28308
    REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"] = 39814
    REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"] = 28300

    -- Basic Regrade Point Fragments
    local sunFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]].average) or 0
    local sunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint"]].average) or 0
    local moonFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]].average) or 0
    local moonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint"]].average) or 0
    local starFragmentPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]].average) or 0
    local starpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint"]].average) or 0
    if sunpointPrice ~= nil then 
        sunFragmentPrice = sunpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Sunpoint Fragment"]].average = sunFragmentPrice
    end
    if moonpointPrice ~= nil then 
        moonFragmentPrice = moonpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Moonpoint Fragment"]].average = moonFragmentPrice
    end
    if starpointPrice ~= nil then 
        starFragmentPrice = starpointPrice / 10
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Starpoint Fragment"]].average = starFragmentPrice
    end
    -- Lucky Regrade Point Shards
    local luckySunShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]].average) or 0
    local luckySunpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint"]].average) or 0
    local luckyMoonShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]].average) or 0
    local luckyMoonpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint"]].average) or 0
    local luckyStarShardPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]].average) or 0
    local luckyStarpointPrice = (AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]] and AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint"]].average) or 0
    if luckySunpointPrice ~= nil then 
        luckySunShardPrice = luckySunpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Sunpoint Shard"]].average = luckySunShardPrice
    end
    if luckyMoonpointPrice ~= nil then 
        luckyMoonShardPrice = luckyMoonpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Moonpoint Shard"]].average = luckyMoonShardPrice
    end
    if luckyStarpointPrice ~= nil then 
        luckyStarShardPrice = luckyStarpointPrice / 3
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]] = {}
        AH_PRICES[REGRADE_BRAZIER_LOOT_IDS["Lucky Starpoint Shard"]].average = luckyStarShardPrice
    end
end 

local function fillInArcheumTreePrices()

end

local function fillInPureOrePrices()
    local PURE_ORE_CONVERSION_MULTIPLIER = 9
    local PURE_ORE_IDS = {}
    PURE_ORE_IDS["Pure Iron Ore"] = 8081
    PURE_ORE_IDS["Pure Copper Ore"] = 8067
    PURE_ORE_IDS["Pure Silver Ore"] = 8085
    PURE_ORE_IDS["Pure Gold Ore"] = 8086
    PURE_ORE_IDS["Pure Archeum Ore"] = 17715

    local ironPrice = (AH_PRICES[8022] and AH_PRICES[8022].average) or 0 -- Iron Ore
    local copperPrice = (AH_PRICES[3411] and AH_PRICES[3411].average) or 0 -- Copper Ore
    local silverPrice = (AH_PRICES[8023] and AH_PRICES[8023].average) or 0 -- Silver Ore
    local goldPrice = (AH_PRICES[8027] and AH_PRICES[8027].average) or 0 -- Gold Ore
    local archeumPrice = (AH_PRICES[1386] and AH_PRICES[1386].average) or 0 -- Archeum Ore
    ironPrice = ironPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Iron Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Iron Ore"]].average = ironPrice
    copperPrice = copperPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Copper Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Copper Ore"]].average = copperPrice
    silverPrice = silverPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Silver Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Silver Ore"]].average = silverPrice
    goldPrice = goldPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Gold Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Gold Ore"]].average = goldPrice
    archeumPrice = archeumPrice * PURE_ORE_CONVERSION_MULTIPLIER
    AH_PRICES[PURE_ORE_IDS["Pure Archeum Ore"]] = {}
    AH_PRICES[PURE_ORE_IDS["Pure Archeum Ore"]].average = archeumPrice
end 

--- Loot Session Details Window — created once, reused on subsequent calls
local lootDetailsWidgets = {}

local function createLootSessionDetailsWindow()
    lootSessionDetailsWindow = api.Interface:CreateWindow("lootSessionDetailsWindow", "Loot Session Details")
    lootSessionDetailsWindow:SetExtent(430, 450)
    lootSessionDetailsWindow:AddAnchor("CENTER", "UIParent", 0, 0)

    local w = lootSessionDetailsWindow
    --- Session Summary Statistics
    local profitLabel = w:CreateChildWidget("label", "lootSessionProfitLabel", 0, true)
    profitLabel.style:SetFontSize(FONT_SIZE.LARGE)
    profitLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(profitLabel, FONT_COLOR.DEFAULT)
    profitLabel:AddAnchor("TOPLEFT", w, 10, 50)
    lootDetailsWidgets.profitLabel = profitLabel

    local durationLabel = w:CreateChildWidget("label", "lootSessionDurationLabel", 0, true)
    durationLabel.style:SetFontSize(FONT_SIZE.LARGE)
    durationLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(durationLabel, FONT_COLOR.DEFAULT)
    durationLabel:AddAnchor("TOPLEFT", w, 250, 50)
    lootDetailsWidgets.durationLabel = durationLabel

    local killsLabel = w:CreateChildWidget("label", "lootSessionKillsLabel", 0, true)
    killsLabel.style:SetFontSize(FONT_SIZE.LARGE)
    killsLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(killsLabel, FONT_COLOR.DEFAULT)
    killsLabel:AddAnchor("TOPLEFT", profitLabel, 0, 24)
    lootDetailsWidgets.killsLabel = killsLabel

    local laborLabel = w:CreateChildWidget("label", "lootSessionLaborLabel", 0, true)
    laborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    laborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(laborLabel, FONT_COLOR.DEFAULT)
    laborLabel:AddAnchor("TOPLEFT", killsLabel, 0, 0)
    lootDetailsWidgets.laborLabel = laborLabel

    local perKillLabel = w:CreateChildWidget("label", "lootSessionPerKillLabel", 0, true)
    perKillLabel.style:SetFontSize(FONT_SIZE.LARGE)
    perKillLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(perKillLabel, FONT_COLOR.DEFAULT)
    perKillLabel:AddAnchor("TOPLEFT", durationLabel, 0, 24)
    lootDetailsWidgets.perKillLabel = perKillLabel

    local perLaborLabel = w:CreateChildWidget("label", "lootSessionPerLaborLabel", 0, true)
    perLaborLabel.style:SetFontSize(FONT_SIZE.LARGE)
    perLaborLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(perLaborLabel, FONT_COLOR.DEFAULT)
    perLaborLabel:AddAnchor("TOPLEFT", perKillLabel, 0, 0)
    lootDetailsWidgets.perLaborLabel = perLaborLabel

    local deleteLabel = w:CreateChildWidget("textbox", "lootSessionDeleteLabel", 0, true)
    deleteLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    deleteLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(deleteLabel, FONT_COLOR.RED)
    deleteLabel:AddAnchor("BOTTOMLEFT", w, 10, -10)
    deleteLabel:SetText("Deleting a session will remove it permanently. \n This action cannot be undone.")
    deleteLabel:SetExtent(350, 24)

    local deleteBtn = w:CreateChildWidget("button", "lootSessionDeleteBtn", 0, true)
    deleteBtn:SetText("Delete Session")
    deleteBtn:AddAnchor("BOTTOMRIGHT", w, -20, -10)
    ApplyButtonSkin(deleteBtn, BUTTON_BASIC.DEFAULT)
    lootDetailsWidgets.deleteBtn = deleteBtn

end

local function drawLootSessionDetails(sessionIndex)
    local session = getSessionByIndex(sessionIndex)
    if session == nil then return end

    -- Create window once, reuse on subsequent calls
    if lootSessionDetailsWindow == nil then
        createLootSessionDetailsWindow()
    end

    local zone = session.zone
    if zone == nil then zone = "Unknown" end
    local items = session.items
    local profitTotal = session.profitTotal
    local laborSpent = session.laborSpent
    local kills = session.kills
    local localTimestamp = session.localTimestamp
    local endTimestamp = session.endTimestamp
    local duration = differenceBetweenTimestamps(endTimestamp, localTimestamp)
    if duration <= 0 then duration = 1 end
    local durationStr = displayTimeString(duration)
    local profitPerHour = profitTotal / (duration / 3600)
    local killsPerHour = kills > 0 and (kills / (duration / 3600)) or 0
    local laborPerHour = laborSpent > 0 and (laborSpent / (duration / 3600)) or 0
    local silverPerLabor = laborSpent > 0 and (profitTotal * 100 / laborSpent) or 0

    -- Update label text
    lootDetailsWidgets.profitLabel:SetText("Profit: " .. string.format('%.0f', profitTotal) .. "g" .. " (" .. string.format('%.0f', profitPerHour) .. "g/hr)")
    lootDetailsWidgets.durationLabel:SetText("Duration: " .. durationStr)
    lootDetailsWidgets.killsLabel:SetText("Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', killsPerHour) .. "/hr)")
    lootDetailsWidgets.laborLabel:SetText("Labor: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', laborPerHour) .. "/hr)")
    lootDetailsWidgets.perKillLabel:SetText("Profit per Kill: " .. string.format('%.2f', kills > 0 and (profitTotal / kills) or 0) .. "g")
    lootDetailsWidgets.perLaborLabel:SetText("Silver Per Labor: " .. string.format('%.2f', silverPerLabor) .. "s")

    -- Flip flop between labor and kills being displayed
    if laborSpent > kills then
        lootDetailsWidgets.killsLabel:Show(false)
        lootDetailsWidgets.perKillLabel:Show(false)
        lootDetailsWidgets.perLaborLabel:Show(true)
        lootDetailsWidgets.laborLabel:Show(true)
    else
        lootDetailsWidgets.laborLabel:Show(false)
        lootDetailsWidgets.perLaborLabel:Show(false)
        lootDetailsWidgets.killsLabel:Show(true)
        lootDetailsWidgets.perKillLabel:Show(true)
    end

    -- Update delete button handler with current sessionIndex
    function lootDetailsWidgets.deleteBtn:OnClick()
        sa.deleteSessionByIndex(pastSessions, archiveFilename, pastSessionsFilename, sessionIndex)

        lootSessionDetailsWindow:Show(false)
        local sessionScrollList = lootWindow.sessionScrollList
        sessionScrollList:DeleteAllDatas()
        maxPage = sa.refreshPageControl(sessionScrollList, pastSessions, pageSize)
        fillSessionTableData(sessionScrollList, 1)
    end
    lootDetailsWidgets.deleteBtn:SetHandler("OnClick", lootDetailsWidgets.deleteBtn.OnClick)

    -- Rebuild items list (destroy old one, create fresh)
    if lootDetailsWidgets.itemsList ~= nil then
        api.Interface:Free(lootDetailsWidgets.itemsList)
        lootDetailsWidgets.itemsList = nil
    end
    local itemsList = W_CTRL.CreateScrollListBox("lootSessionItemsList", lootSessionDetailsWindow, "TYPE2")
    itemsList:AddAnchor("TOPLEFT", lootSessionDetailsWindow, 10, 100)
    itemsList:AddAnchor("BOTTOMRIGHT", lootSessionDetailsWindow, -10, -60)
    itemsList:SetExtent(400, 300)
    lootDetailsWidgets.itemsList = itemsList
    local sortedItemsByAHPrice = {}
    for itemId, itemCount in pairs(items) do
        local cleanedItemId = getCleanedItemId(itemId)
        local itemPrice = AH_PRICES[tonumber(cleanedItemId)]
        local totalValue = 0
        if itemPrice ~= nil then
            totalValue = itemCount * (itemPrice.average or 0)
        end
        table.insert(sortedItemsByAHPrice, {itemId = itemId, itemCount = itemCount, totalValue = totalValue})
    end
    table.sort(sortedItemsByAHPrice, function(a, b)
        return a.totalValue > b.totalValue
    end)
    local count = 1
    for _, item in ipairs(sortedItemsByAHPrice) do
        local itemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(item.itemId)))
        local displayStr = itemInfo.name .. " x" .. item.itemCount .. " (" .. string.format('%.0f', item.totalValue) .. "g)"
        itemsList:AppendItem(displayStr, count)
        count = count + 1
    end

    lootSessionDetailsWindow:Show(true)
end

local function OnUpdate(dt)
    if displayRefreshCounter + dt > DISPLAY_REFRESH_MS then
        displayRefreshCounter = 0
        if displayDirty and lootUIInitialized and paystubDisplayWindow ~= nil and paystubDisplayWindow:IsVisible() then
            displayDirty = false
            local sessionScrollList = lootWindow.sessionScrollList
            sessionScrollList.pageControl.maxPage = maxPage
            fillSessionTableData(sessionScrollList, 1)
            sessionScrollList.pageControl:SetCurrentPage(1, true)
        end
    end
    displayRefreshCounter = displayRefreshCounter + dt

    -- Labor used timer for excluding from kill count
    if laborUsedTimer + dt > LABOR_USED_TIMER_RATE then 
        laborUsedTimer = 0
        laborUsed = false
        -- api.Log:Info("Labor used timer reset")
    end
    laborUsedTimer = laborUsedTimer + dt

    if sessionClockRefreshTimer + dt > SESSION_CLOCK_REFRESH_RATE then
        sessionClockRefreshTimer = 0
        lootWindow.lootTrackerOverlay.timerLabel:SetText(displayOverlayTimeString(lootTrackerSessionTimer / 1000))
        if currentSession ~= nil then
            local elapsedSecs = lootTrackerSessionTimer / 1000
            if elapsedSecs > 0 then
                local profitPerHour = currentSession["profitTotal"] / elapsedSecs * 3600
                local killsPerHour = currentSession["kills"] / elapsedSecs * 3600
                lootWindow.lootTrackerOverlay.profitLabel:SetText("Profit: " .. string.format('%.0f', tostring(currentSession["profitTotal"])) .. "g" .. " (" .. string.format('%.0f', tostring(profitPerHour)) .. "g/hr)")
                lootWindow.lootTrackerOverlay.killsLabel:SetText("Kills: " .. tostring(currentSession["kills"]) .. " (" .. string.format('%.0f', tostring(killsPerHour)) .. "/hr)")
            else
                lootWindow.lootTrackerOverlay.profitLabel:SetText("Profit: " .. string.format('%.0f', tostring(currentSession["profitTotal"])) .. "g")
                lootWindow.lootTrackerOverlay.killsLabel:SetText("Kills: " .. tostring(currentSession["kills"]))
            end
            local laborSpent = currentSession["laborSpent"]
            if laborSpent > 0 then
                local silverPerLabor = currentSession["profitTotal"] * 100 / laborSpent
                lootWindow.lootTrackerOverlay.laborLabel:SetText("Labor: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', tostring(silverPerLabor)) .. "s/labor)")
            else
                lootWindow.lootTrackerOverlay.laborLabel:SetText("Labor: " .. tostring(laborSpent))
            end
        else
            lootWindow.lootTrackerOverlay.profitLabel:SetText("Profit: 0g")
            lootWindow.lootTrackerOverlay.killsLabel:SetText("Kills: 0")
            lootWindow.lootTrackerOverlay.laborLabel:SetText("Labor: 0")
        end
    end
    sessionClockRefreshTimer = sessionClockRefreshTimer + dt

    if currentSession ~= nil and sessionPaused ~= true then 
        lootTrackerSessionTimer = lootTrackerSessionTimer + dt
    end 
    
end 

--- Session Scroll List Functions
local function SessionSetFunc(subItem, data, setValue)
    if setValue then
        -- Data Assignments
        local sessionIndex = data.index
        local packObject = nil
        local packName = "Unknown Pack (id: " .. tostring(data.packId) .. ")" 
        if packObject ~= nil then 
            if packObject.name ~= nil then packName = packObject.name end
        end
        local items = data.items
        local lootZone = data.zone
        local kills = data.kills
        local laborSpent = data.laborSpent or 0
        local profitTotal = data.profitTotal
        local costTotal = data.costTotal
        local date = api.Time:TimeToDate(data.localTimestamp)
        local duration = differenceBetweenTimestamps(data.endTimestamp, data.localTimestamp)
        local durationStr = displayTimeString(duration)

        -- Display Strings
        local leftTextStr = ""
        if items then
            local highestCrateItemId, highestCrateItemCount = nil, 0

            for itemId, itemCount in pairs(items) do
                local cleanedItemId = getCleanedItemId(itemId)
                local itemInfo = api.Item:GetItemInfoByType(tonumber(cleanedItemId))
                if itemInfo and (string.find(string.lower(itemInfo.name), "crate") or string.find(string.lower(itemInfo.name), "research bundle")) and itemCount > highestCrateItemCount then
                    highestCrateItemId = itemId
                    highestCrateItemCount = itemCount
                end
            end

            if highestCrateItemId then
                local crateItemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(highestCrateItemId)))
                local durationInHours = duration / 3600
                local cratesPerHour = highestCrateItemCount / durationInHours
                leftTextStr = crateItemInfo.name .. " x" .. tostring(highestCrateItemCount) .. " (" .. string.format('%.0f', cratesPerHour) .. "/hr)"
            else
                leftTextStr = "No crates found"
            end
        end
        if items then
            local highestCoinpurseItemId, highestCoinpurseItemCount = nil, 0

            for itemId, itemCount in pairs(items) do
                local cleanedItemId = getCleanedItemId(itemId)
                local itemInfo = api.Item:GetItemInfoByType(tonumber(cleanedItemId))
                if itemInfo and string.find(string.lower(itemInfo.name), "coinpurse") and itemCount > highestCoinpurseItemCount then
                    highestCoinpurseItemId = itemId
                    highestCoinpurseItemCount = itemCount
                end
            end

            if highestCoinpurseItemId then
                local coinpurseItemInfo = api.Item:GetItemInfoByType(tonumber(getCleanedItemId(highestCoinpurseItemId)))
                local durationInHours = duration / 3600
                local coinpursesPerHour = highestCoinpurseItemCount / durationInHours
                leftTextStr = leftTextStr .. "\n" .. coinpurseItemInfo.name .. " x" .. tostring(highestCoinpurseItemCount) .. " (" .. string.format('%.0f', coinpursesPerHour) .. "/hr)"
            else
                leftTextStr = leftTextStr .. "\nNo coinpurses found"
            end
        end

        local rightTextStr = "Profit: " .. tostring(profitTotal)
        if type(profitTotal) == "number" then 
            rightTextStr = "Profit: " .. string.format('%.0f', tostring(profitTotal)) .. "g" .. " (" .. string.format('%.0f', profitTotal / (duration / 3600)) .. "g/hr)"
        end 
        if kills > 0 then 
            rightTextStr = rightTextStr .. " \n " .. "Kills: " .. tostring(kills) .. " (" .. string.format('%.0f', kills / (duration / 3600)) .. "/hr)"
        else 
            rightTextStr = rightTextStr .. " \n " .. "Labor Spent: " .. tostring(laborSpent) .. " (" .. string.format('%.0f', laborSpent / (duration / 3600)) .. "/hr)"
        end 
        -- api.Log:Info(subItem.subItemIcon)
        -- api.Log:Info(data.items)
        if items then 
            local highestItemId, highestItemCount = nil, 0
            
            for itemId, itemCount in pairs(items) do
                if itemCount > highestItemCount then
                    highestItemId = itemId
                    highestItemCount = itemCount
                end
            end
            if highestItemId == nil then 
                F_SLOT.SetIconBackGround(subItem.subItemIcon, "game/ui/icon/icon_item_1338.dds")
            else 
                highestItemId = getCleanedItemId(highestItemId)
                local itemInfo = api.Item:GetItemInfoByType(tonumber(highestItemId))
                if itemInfo ~= nil then 
                    -- api.Log:Info(itemInfo.name)
                    F_SLOT.SetIconBackGround(subItem.subItemIcon, itemInfo.path) 
                end 
            end
        end

        local titleStr = "Unknown Zone Loot Session"
        
        
        if kills > laborSpent then 
            -- Larceny session, depicted by more kills than labor spent
            if lootZone ~= nil then 
                titleStr = lootZone .. " Loot Session"
            end 
            subItem.bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
        else
            -- Harvesting session
            if lootZone ~= nil then 
                titleStr = lootZone .. " Harvesting Session"
            end 

            subItem.bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
        end 
        titleStr = titleStr .. " (".. durationStr .. ") "
        subItem.id = id
        subItem.textboxLeft:SetText(leftTextStr)
        subItem.textboxRight:SetText(rightTextStr)
        subItem.sessionTitle:SetText(titleStr)
        subItem.sessionDateLabel:SetText(string.format("%02d/%02d/%04d", date.month, date.day, date.year))
        function subItem.clickOverlay:OnClick()
            drawLootSessionDetails(sessionIndex)
        end
        subItem.clickOverlay:SetHandler("OnClick", subItem.clickOverlay.OnClick)
    end
end

local function SessionsColumnLayoutSetFunc(frame, rowIndex, colIndex, subItem)
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
    sessionTitle:SetText("Unknown Loot Session")
    sessionTitle:AddAnchor("TOPLEFT", subItem, 10, 10)
    sessionTitle:SetAutoResize(true)
    sessionTitle.style:SetAlign(ALIGN.LEFT)
    -- Pack Item Icon 
    local subItemIcon = CreateItemIconButton("subItemIcon", sessionTitle)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    subItemIcon:AddAnchor("TOPLEFT", sessionTitle, 0, 10)
    subItem.subItemIcon = subItemIcon

    -- Top-right Session "Is paid?" Label
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
    -- Interact Layer overtop of everything
    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    -- function clickOverlay:OnClick()
    --     api.Log:Info("Ding!")
    -- end 
    -- clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
    subItem.clickOverlay = clickOverlay
end

local function initLootUI()
    if lootUIInitialized then return end
    lootUIInitialized = true

    local sessionScrollList = lootWindow.sessionScrollList
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

    local settings = api.GetSettings("your_paystub")
    local lootTrackerOverlay = lootWindow.lootTrackerOverlay
    local toggleOverlayBtn = lootWindow:CreateChildWidget("button", "toggleOverlayBtn", 0, true)
    toggleOverlayBtn:SetText("Toggle Overlay")
    toggleOverlayBtn:AddAnchor("BOTTOMRIGHT", lootWindow, -10, 50)
    ApplyButtonSkin(toggleOverlayBtn, BUTTON_BASIC.DEFAULT)
    function toggleOverlayBtn:OnClick()
        if lootTrackerOverlay:IsVisible() then
            lootTrackerOverlay:Show(false)
            settings.lootOverlayVisible = false
        else
            lootTrackerOverlay:Show(true)
            settings.lootOverlayVisible = true
        end
        api.SaveSettings()
    end
    toggleOverlayBtn:SetHandler("OnClick", toggleOverlayBtn.OnClick)
end

local function OnLoad()
    -- Initializing addon-wide variables
    local settings = api.GetSettings("your_paystub")
    pastSessionsFilename = "your_paystub_loot_sessions.lua"
    AH_PRICES = require("your_paystub/data/auction_house_prices")
    -- Initialize the addon's empty window
    yourPaystubWindow = api.Interface:CreateEmptyWindow("yourPaystubWindow", "UIParent")
    sessionPaused = false

    -- Fill in AH prices for noble's, jester's, prince's, queen's and ancestral crates
    fillInAHPricesForCrates()
    -- Fill in regrade brazier loot prices
    fillInRegradeBrazierPrices()
    -- Fill in archeum tree loot prices
    fillInArcheumTreePrices()
    -- Fill in pure ore prices
    fillInPureOrePrices()
    
    -- Load previous sessions, or make empty file.
    pastSessions, maxPage = sa.loadOrInitSessions(pastSessionsFilename, pageSize)

    function yourPaystubWindow:OnEvent(event, ...)
        if event == "REMOVED_ITEM" then      
            removedItem(unpack(arg))
        end
        if event == "ADDED_ITEM" then
            lootedItem(unpack(arg))
        end 
        if event == "LABORPOWER_CHANGED" then
            laborPointsChanged(unpack(arg))
        end
        if event == "EXP_CHANGED" then
            trackKill(unpack(arg))
        end
        if event == "STORE_SELL" then
            -- soldAtResourceTrader(unpack(arg))
        end
        if event == "CHAT_JOINED_CHANNEL" then 
            updateLastKnownChannel(unpack(arg))
        end 
    end
    yourPaystubWindow:SetHandler("OnEvent", yourPaystubWindow.OnEvent)
    yourPaystubWindow:RegisterEvent("ADDED_ITEM")
    yourPaystubWindow:RegisterEvent("REMOVED_ITEM")
    yourPaystubWindow:RegisterEvent("LABORPOWER_CHANGED")
    yourPaystubWindow:RegisterEvent("EXP_CHANGED")
    yourPaystubWindow:RegisterEvent("STORE_SELL")
    yourPaystubWindow:RegisterEvent("CHAT_JOINED_CHANNEL")

    -- Keep lootWindow reference for overlay
    lootWindow = paystubDisplayWindow.tab.window[2].lootWindow

    -- Initialize Loot Tracker overlay
    local lootTrackerOverlay = api.Interface:CreateEmptyWindow("lootTrackerOverlay", "UIParent")
    local lootOverlayX = settings.lootOverlayX or 0
    local lootOverlayY = settings.lootOverlayY or 0
    local lootOverlayVisible = true
    if settings.lootOverlayVisible ~= nil then 
        lootOverlayVisible = settings.lootOverlayVisible
    end
    lootTrackerOverlay:SetExtent(220, 80)
    if lootOverlayX == 0 and lootOverlayY == 0 then 
        lootTrackerOverlay:AddAnchor("CENTER", "UIParent", 0, 0)
    else
        lootTrackerOverlay:AddAnchor("TOPLEFT", "UIParent", lootOverlayX, lootOverlayY)
    end 
    lootTrackerOverlay:Show(lootOverlayVisible)
    lootTrackerOverlay:Clickable(false)
    local bg = lootTrackerOverlay:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetColor(ConvertColor(0),ConvertColor(0),ConvertColor(0),0.5)
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", lootTrackerOverlay, 0, 0)
    -- bg:Show(true)
    lootTrackerOverlay.bg = bg
    -- Timer clock icon and label
    local timerLabel = lootTrackerOverlay:CreateChildWidget("label", "timerLabel", 0, true)
    timerLabel.style:SetShadow(true)
    timerLabel.style:SetAlign(ALIGN.RIGHT)
    timerLabel:AddAnchor("TOPRIGHT", lootTrackerOverlay, "TOPRIGHT", -15, 15)
    timerLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
    timerLabel:SetText("00:00:00")
    local clockIcon = timerLabel:CreateChildWidget("label", "clockIcon", 0, true)  
    clockIcon:AddAnchor("TOPLEFT", timerLabel, "TOPLEFT", -80, -14)
    local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
    clockIconTexture:SetTextureInfo("clock")
    clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)
    -- Profit, Labor and kill count labels
    local profitLabel = lootTrackerOverlay:CreateChildWidget("label", "profitLabel", 0, true)
    profitLabel.style:SetShadow(true)
    profitLabel.style:SetAlign(ALIGN.LEFT)
    profitLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 35)
    profitLabel.style:SetFontSize(FONT_SIZE.SMALL)
    profitLabel:SetText("Profit: 0g")
    local killsLabel = lootTrackerOverlay:CreateChildWidget("label", "killsLabel", 0, true)
    killsLabel.style:SetShadow(true)
    killsLabel.style:SetAlign(ALIGN.LEFT)
    killsLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 50)
    killsLabel.style:SetFontSize(FONT_SIZE.SMALL)
    killsLabel:SetText("Kills: 0")
    local laborLabel = lootTrackerOverlay:CreateChildWidget("label", "laborLabel", 0, true)
    laborLabel.style:SetShadow(true)
    laborLabel.style:SetAlign(ALIGN.LEFT)
    laborLabel:AddAnchor("TOPLEFT", lootTrackerOverlay, "TOPLEFT", 15, 65)
    laborLabel.style:SetFontSize(FONT_SIZE.SMALL)
    laborLabel:SetText("Labor: 0")
    -- Start and save buttons
    local startBtn = lootTrackerOverlay:CreateChildWidget("button", "startBtn", 0, true)
	startBtn:SetText("Start")
	startBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, -10, 30)
    startBtn.bg = startBtn:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
    startBtn.bg:SetColor(ConvertColor(100),ConvertColor(100),ConvertColor(100),0.7)
    startBtn.bg:SetTextureInfo("bg_quest")
    startBtn.bg:AddAnchor("TOPLEFT", startBtn, 0, 0)
    startBtn.bg:AddAnchor("BOTTOMRIGHT", startBtn, 0, 0)
    -- startBtn.bg:Show(true)
    startBtn:SetExtent(50,20)
    local saveBtn = lootTrackerOverlay:CreateChildWidget("button", "saveBtn", 0, true)
	saveBtn:SetText("End")
	saveBtn:AddAnchor("TOPRIGHT", lootTrackerOverlay, -10, 52)
	saveBtn.bg = saveBtn:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
    saveBtn.bg:SetColor(ConvertColor(100),ConvertColor(100),ConvertColor(100),0.7)
    saveBtn.bg:SetTextureInfo("bg_quest")
    saveBtn.bg:AddAnchor("TOPLEFT", saveBtn, 0, 0)
    saveBtn.bg:AddAnchor("BOTTOMRIGHT", saveBtn, 0, 0)
    -- saveBtn.bg:Show(true)
    saveBtn:SetExtent(50,20)
    -- Click handlers for start/save buttons
    function startBtn:OnClick()
        startLootTrackerSession()
    end
    startBtn:SetHandler("OnClick", startBtn.OnClick)
    function saveBtn:OnClick()
        endLootTrackerSession()
    end
    saveBtn:SetHandler("OnClick", saveBtn.OnClick)
    --- Add dragable bar across top
    local moveWnd = lootTrackerOverlay:CreateChildWidget("label", "moveWnd", 0, true)
    moveWnd:AddAnchor("TOPLEFT", lootTrackerOverlay, 0, 0)
    moveWnd:AddAnchor("TOPRIGHT", lootTrackerOverlay, 0, 0)
    moveWnd:SetHeight(30)
    moveWnd.style:SetFontSize(FONT_SIZE.LARGE)
    moveWnd.style:SetAlign(ALIGN.LEFT)
    moveWnd:SetText("   Loot Tracker")
    ApplyTextColor(moveWnd, FONT_COLOR.WHITE)
    -- Drag handlers for dragable bar
    function moveWnd:OnDragStart()
        if api.Input:IsShiftKeyDown() then
            lootTrackerOverlay:StartMoving()
            api.Cursor:ClearCursor()
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end
    moveWnd:SetHandler("OnDragStart", moveWnd.OnDragStart)
    function moveWnd:OnDragStop()
        lootTrackerOverlay:StopMovingOrSizing()
        api.Cursor:ClearCursor()
        local currentX, currentY = lootTrackerOverlay:GetOffset()
        settings.lootOverlayX = currentX
        settings.lootOverlayY = currentY
        api.SaveSettings()
    end
    moveWnd:SetHandler("OnDragStop", moveWnd.OnDragStop)
    moveWnd:EnableDrag(true)
    lootWindow.lootTrackerOverlay = lootTrackerOverlay

    api.On("UPDATE", OnUpdate)
    api.SaveSettings()
end

local function OnUnload()
    local settings = api.GetSettings("your_paystub")
    if lootSessionDetailsWindow ~= nil then
        lootSessionDetailsWindow:Show(false)
        api.Interface:Free(lootSessionDetailsWindow)
        lootSessionDetailsWindow = nil
        lootDetailsWidgets = {}
    end
    if lootWindow ~= nil and lootWindow.lootTrackerOverlay ~= nil then
        lootWindow.lootTrackerOverlay:Show(false)
        api.Interface:Free(lootWindow.lootTrackerOverlay)
    end
    api.Interface:Free(yourPaystubWindow)
    api.On("UPDATE", function() return end)
    yourPaystubWindow = nil
    lootWindow = nil
    api.SaveSettings()
end

your_loot_addon.OnLoad = OnLoad
your_loot_addon.OnUnload = OnUnload
your_loot_addon.initUI = initLootUI

return your_loot_addon
