fishing_helper = {}

--- Known fish item IDs (by grade) for every fishable species.
--> Sourced from observed fish-stand turn-ins; keeps IsAFishById fast (no name lookup needed).
local fishIds = {
    [27604] = true, [27603] = true, [27602] = true, -- Blue Marlin
    [27601] = true, [27600] = true, [27599] = true, -- Sailfish
    [27501] = true, [27458] = true, [27457] = true, -- Bluefin
    [39735] = true, [39734] = true, [39733] = true, -- Sunfish
    [27607] = true, [27606] = true, [27605] = true, -- Sturgeon
    [27504] = true, [27503] = true, [27502] = true, -- Carp
    [42160] = true, [27612] = true, [27611] = true, -- Electric Eel
    [27610] = true, [27609] = true, [27608] = true, -- Arowana
    [31691] = true, [30428] = true, [30422] = true, [30429] = true,
    [32064] = true, [32065] = true, [32066] = true,
    [32067] = true, [32068] = true, [32069] = true,
    [32070] = true, [32071] = true, [32072] = true,
    [32073] = true, [32074] = true, [32075] = true,
    [32076] = true, [32077] = true, [32078] = true,
    [32085] = true, [32086] = true, [32087] = true,
    [32088] = true, [32089] = true, [32090] = true,
    [32091] = true, [32092] = true, [32093] = true,
    [32094] = true, [32095] = true, [32096] = true,
    [32097] = true, [32098] = true, [32099] = true,
    [32100] = true, [32101] = true, [32102] = true,
    [36369] = true, [36370] = true, [36371] = true,
    [40828] = true, [40829] = true, [40830] = true,
    [40831] = true, [40832] = true, [40833] = true,
    [40834] = true, [40835] = true, [40836] = true,
    [40837] = true, [40838] = true, [40839] = true,
    [40840] = true, [40841] = true, [40842] = true,
}
fishing_helper.fishIds = fishIds

--- Name substring fallback for fish not covered by the ID table above
--> (new patches, localized names, etc). Checked case-insensitively.
local fishNameKeywords = {
    "fry pack", "gargantuan", "marlin", "marlim", "sturgeon", "estur",
    "sailfish", "veleiro", "tuna", "atum", "snapper", "pargo", "carp",
    "carpa", "pike", "puffer", "pufferfish", "blowfish", "baiacu", "arowana", "mullet", "tainha",
    "barramundi", "coelacanth", "celacanto", "sunfish", "peixe", "piranha",
    "arapaima", "pirarucu", "bass", "robalo", "koi", "bluefin"
}
fishing_helper.fishNameKeywords = fishNameKeywords

function fishing_helper:IsAFishByName(itemName)
    if itemName == nil then return false end
    local nameToCheck = string.lower(itemName)
    for _, keyword in ipairs(fishNameKeywords) do
        if string.find(nameToCheck, keyword) then
            return true
        end
    end
    return false
end

function fishing_helper:IsAFishById(itemId)
    itemId = tonumber(itemId)
    if itemId == nil then return false end
    if fishIds[itemId] then return true end

    local itemInfo = api.Item:GetItemInfoByType(itemId)
    if itemInfo == nil or itemInfo.name == nil then return false end
    return fishing_helper:IsAFishByName(itemInfo.name)
end

return fishing_helper
