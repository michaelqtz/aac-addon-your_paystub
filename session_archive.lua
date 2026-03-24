local session_archive = {}

local MAX_RECENT_SESSIONS = 200

-- Per-filename archive state (keyed by archiveFilename)
local archiveState = {}

local function getState(archiveFilename)
    if not archiveState[archiveFilename] then
        archiveState[archiveFilename] = { loaded = false, sessions = nil }
    end
    return archiveState[archiveFilename]
end

local function ensureArchiveLoaded(pastSessions, archiveFilename)
    local state = getState(archiveFilename)
    if not state.loaded then
        state.sessions = api.File:Read(archiveFilename)
        if state.sessions == nil then state.sessions = { sessions = {} } end
        state.loaded = true
        pastSessions.archiveCount = #state.sessions.sessions
    end
    return state.sessions
end

function session_archive.getSessionByIndex(pastSessions, archiveFilename, index)
    local recentCount = pastSessions.sessions and #pastSessions.sessions or 0
    if index <= recentCount then
        return pastSessions.sessions[index]
    end
    local archive = ensureArchiveLoaded(pastSessions, archiveFilename)
    local archiveIndex = #archive.sessions - (index - recentCount) + 1
    return archive.sessions[archiveIndex]
end

function session_archive.getTotalSessionCount(pastSessions)
    return #pastSessions.sessions + (pastSessions.archiveCount or 0)
end

function session_archive.archiveOverflow(pastSessions, archiveFilename, onOverflow)
    if #pastSessions.sessions <= MAX_RECENT_SESSIONS then return end
    local archive = ensureArchiveLoaded(pastSessions, archiveFilename)
    while #pastSessions.sessions > MAX_RECENT_SESSIONS do
        local overflow = table.remove(pastSessions.sessions)
        if onOverflow then onOverflow(overflow) end
        table.insert(archive.sessions, overflow)
    end
    pastSessions.archiveCount = #archive.sessions
    api.File:Write(archiveFilename, archive)
end

function session_archive.deleteSessionByIndex(pastSessions, archiveFilename, pastSessionsFilename, index)
    local recentCount = #pastSessions.sessions
    if index <= recentCount then
        table.remove(pastSessions.sessions, index)
        api.File:Write(pastSessionsFilename, pastSessions)
    else
        local archive = ensureArchiveLoaded(pastSessions, archiveFilename)
        local archiveIndex = #archive.sessions - (index - recentCount) + 1
        if archiveIndex >= 1 and archiveIndex <= #archive.sessions then
            table.remove(archive.sessions, archiveIndex)
            pastSessions.archiveCount = #archive.sessions
            api.File:Write(archiveFilename, archive)
            api.File:Write(pastSessionsFilename, pastSessions)
        end
    end
end

function session_archive.loadOrInitSessions(pastSessionsFilename, pageSize)
    local pastSessions = api.File:Read(pastSessionsFilename)
    local maxPage
    if pastSessions ~= nil then
        if pastSessions.sessions ~= nil then
            local total = session_archive.getTotalSessionCount(pastSessions)
            maxPage = math.ceil(total / pageSize)
        else
            maxPage = 1
        end
    else
        pastSessions = { sessions = {} }
        api.File:Write(pastSessionsFilename, pastSessions)
        maxPage = 1
    end
    return pastSessions, maxPage
end

function session_archive.refreshPageControl(sessionScrollList, pastSessions, pageSize)
    local total = session_archive.getTotalSessionCount(pastSessions)
    local maxPage = math.max(1, math.ceil(total / pageSize))
    sessionScrollList.pageControl.maxPage = maxPage
    sessionScrollList.pageControl:SetCurrentPage(1, true)
    return maxPage
end

-- Shared helpers (duplicated across loot.lua, packs.lua, accounting.lua)
function session_archive.split(s, sep)
    local fields = {}
    local sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

function session_archive.ConvertColor(color)
    return color / 255
end

function session_archive.differenceBetweenTimestamps(time1, time2)
    local time1Suffix = string.sub(time1, (#time1 - 2) * -1)
    local time2Suffix = string.sub(time2, (#time2 - 2) * -1)
    local timeDiff = tonumber(time1Suffix) - tonumber(time2Suffix)
    return timeDiff
end

function session_archive.displayTimeString(timeInSeconds)
    local seconds = math.floor(timeInSeconds) % 60
    local minutes = math.floor(timeInSeconds / (1*60)) % 60
    local hours = math.floor(timeInSeconds / (1*60*60)) % 24
    return string.format("%02dh %02dm", hours, minutes)
end

session_archive.MAX_RECENT_SESSIONS = MAX_RECENT_SESSIONS

return session_archive
