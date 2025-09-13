
local your_paystub_addon = {
	name = "Your Paystub",
	author = "Michaelqt",
	version = "1.4.2",
	desc = "Keep track of how much you get paid!"
}

local packsAddon = require("your_paystub/packs")
local lootAddon = require("your_paystub/loot")
local accountingADdon = require("your_paystub/accounting")

paystubDisplayWindow = nil
local paystubBtn
local windowX = 600
local windowY = 800


local function ConvertColor(color)
    return color / 255
end 

local function CreateCommerceWindow(wndParent)
    -- Commerce Parent Window
    local wnd = wndParent:CreateChildWidget("emptywidget", "commerceWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Pending Pack Payments")
    title:AddAnchor("TOP", wnd, 0, 10)
    -- Session-holding Scroll List
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 4)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
    -- packsAddon:initializeCommerceSessionTable()

    -- Session 1
    -- local session1 = wnd:CreateChildWidget("emptywidget", "session1", 0, true)
    -- session1:SetExtent(580, 70)
    -- local bg = session1:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    -- bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    -- bg:SetTextureInfo("bg_quest")
    -- bg:AddAnchor("TOPLEFT", session1, -10, -10)
    -- bg:AddAnchor("BOTTOMRIGHT", session1, 10, 10)
    -- bg:Show(true)
    -- session1:AddAnchor("TOPLEFT", title, -200, 40)
    -- local session1Label = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1Label.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1Label, FONT_COLOR.DEFAULT)
    -- session1Label:SetText("Diamond Shores Turn-in (11/18/2024)")
    -- session1Label:AddAnchor("TOPLEFT", session1, 0, 0)
    -- session1Label:SetAutoResize(true)
    -- session1Label.style:SetAlign(ALIGN.LEFT)
    -- local session1PaidLabel = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PaidLabel, FONT_COLOR.DEFAULT)
    -- session1PaidLabel:SetText("Payout: 3h 12m")
    -- session1PaidLabel:AddAnchor("TOPRIGHT", session1, 0, 0)
    -- session1PaidLabel:SetAutoResize(true)
    -- session1PaidLabel.style:SetAlign(ALIGN.RIGHT)
    -- local subItemIcon = CreateItemIconButton("subItemIcon", session1Label)
    -- subItemIcon:Show(true)
    -- F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    -- F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    -- subItemIcon:AddAnchor("TOPLEFT", session1Label, 0, 16)

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
    -- -- Session 2
    -- local session2 = wnd:CreateChildWidget("emptywidget", "session2", 0, true)
    -- session2:SetExtent(580, 70)
    -- local bg = session2:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    -- bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
    -- bg:SetTextureInfo("bg_quest")
    -- bg:AddAnchor("TOPLEFT", session2, -10, -10)
    -- bg:AddAnchor("BOTTOMRIGHT", session2, 10, 10)
    -- bg:Show(true)
    -- session2:AddAnchor("TOPLEFT", session1, 0, 90)
    -- local session2Label = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2Label.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2Label, FONT_COLOR.DEFAULT)
    -- session2Label:SetText("Solzreed Peninsula Turn-in (11/13/2024)")
    -- session2Label:AddAnchor("TOPLEFT", session2, 0, 0)
    -- session2Label:SetAutoResize(true)
    -- session2Label.style:SetAlign(ALIGN.LEFT)
    -- local session2PaidLabel = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PaidLabel, FONT_COLOR.DEFAULT)
    -- session2PaidLabel:SetText("PAID!")
    -- session2PaidLabel:AddAnchor("TOPRIGHT", session2, 0, 0)
    -- session2PaidLabel:SetAutoResize(true)
    -- session2PaidLabel.style:SetAlign(ALIGN.RIGHT)
    -- local subItemIcon = CreateItemIconButton("subItemIcon", session2Label)
    -- subItemIcon:Show(true)
    -- F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    -- F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    -- subItemIcon:AddAnchor("TOPLEFT", session2Label, 0, 16)

    -- local session2PackAmt = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackAmt.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackAmt, FONT_COLOR.DEFAULT)
    -- session2PackAmt:SetText("Rokhala Aged Cheese x17 (Charcoal x1462)")
    -- session2PackAmt:AddAnchor("TOPLEFT", session2, 50, 40)
    -- session2PackAmt:SetAutoResize(true)
    -- session2PackAmt.style:SetAlign(ALIGN.LEFT)
    -- local session2PackLabor = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackLabor.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackLabor, FONT_COLOR.DEFAULT)
    -- session2PackLabor:SetText("Labor: 2652")
    -- session2PackLabor:AddAnchor("TOPRIGHT", session2, 0, 20)
    -- session2PackLabor:SetAutoResize(true)
    -- session2PackLabor.style:SetAlign(ALIGN.RIGHT)
    -- local session2PackPay = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackPay.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackPay, FONT_COLOR.DEFAULT)
    -- session2PackPay:SetText("Total: 2529.26g")
    -- session2PackPay:AddAnchor("TOPRIGHT", session2, 0, 40)
    -- session2PackPay:SetAutoResize(true)
    -- session2PackPay.style:SetAlign(ALIGN.RIGHT)
    -- local session2PackProfit = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackProfit.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackProfit, FONT_COLOR.DEFAULT)
    -- session2PackProfit:SetText("Profit: 1937.23g")
    -- session2PackProfit:AddAnchor("TOPRIGHT", session2, 0, 60)
    -- session2PackProfit:SetAutoResize(true)
    -- session2PackProfit.style:SetAlign(ALIGN.RIGHT)

    return wnd
end 

local function CreateLootTrackerWindow(wndParent)
    -- Loot Parent Window
    local wnd = wndParent:CreateChildWidget("emptywidget", "lootWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Loot Tracker")
    title:AddAnchor("TOP", wnd, 0, 10)
    -- Session-holding Scroll List
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 4)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
    -- wnd:AddAnchor("TOP", wndParent, 0, 0)
    -- local title = wnd:CreateChildWidget("label", "title", 0, true)
    -- title:SetAutoResize(true)
    -- title:SetHeight(FONT_SIZE.XLARGE)
    -- title.style:SetAlign(ALIGN.CENTER)
    -- title.style:SetFontSize(FONT_SIZE.XLARGE)
    -- ApplyTextColor(title, FONT_COLOR.TITLE)
    -- title:SetText("Previous Loot Sessions")
    -- title:AddAnchor("TOP", wnd, 0, 10)
    -- -- Session 1
    -- local session1 = wnd:CreateChildWidget("emptywidget", "session1", 0, true)
    -- session1:SetExtent(580, 70)
    -- local bg = session1:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    -- bg:SetColor(ConvertColor(210),ConvertColor(94),ConvertColor(84),0.4)
    -- bg:SetTextureInfo("bg_quest")
    -- bg:AddAnchor("TOPLEFT", session1, -10, -10)
    -- bg:AddAnchor("BOTTOMRIGHT", session1, 10, 10)
    -- bg:Show(true)
    -- session1:AddAnchor("TOPLEFT", title, -200, 40)
    -- local session1Label = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1Label.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1Label, FONT_COLOR.DEFAULT)
    -- session1Label:SetText("Hasla, 1746 kills (11/18/2024)")
    -- session1Label:AddAnchor("TOPLEFT", session1, 0, 0)
    -- session1Label:SetAutoResize(true)
    -- session1Label.style:SetAlign(ALIGN.LEFT)
    -- local session1PaidLabel = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PaidLabel, FONT_COLOR.DEFAULT)
    -- session1PaidLabel:SetText("Duration: 1h 19m")
    -- session1PaidLabel:AddAnchor("TOPRIGHT", session1, 0, 0)
    -- session1PaidLabel:SetAutoResize(true)
    -- session1PaidLabel.style:SetAlign(ALIGN.RIGHT)
    -- local subItemIcon = CreateItemIconButton("subItemIcon", session1Label)
    -- subItemIcon:Show(true)
    -- F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    -- F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_3618.dds")
    -- subItemIcon:AddAnchor("TOPLEFT", session1Label, 0, 16)

    -- local session1LootAmt1 = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1LootAmt1.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1LootAmt1, FONT_COLOR.DEFAULT)
    -- session1LootAmt1:SetText("Jester's Crate x291 (1479.01g)")
    -- session1LootAmt1:AddAnchor("TOPLEFT", session1, 50, 20)
    -- session1LootAmt1:SetAutoResize(true)
    -- session1LootAmt1.style:SetAlign(ALIGN.LEFT)
    -- local session1LootAmt2 = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1LootAmt2.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1LootAmt2, FONT_COLOR.DEFAULT)
    -- session1LootAmt2:SetText("Lost Metallic Crate x5 (112.39g)")
    -- session1LootAmt2:AddAnchor("TOPLEFT", session1, 50, 40)
    -- session1LootAmt2:SetAutoResize(true)
    -- session1LootAmt2.style:SetAlign(ALIGN.LEFT)
    -- local session1PackLabor = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackLabor.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackLabor, FONT_COLOR.DEFAULT)
    -- session1PackLabor:SetText("Labor: 1746")
    -- session1PackLabor:AddAnchor("TOPRIGHT", session1, 0, 20)
    -- session1PackLabor:SetAutoResize(true)
    -- session1PackLabor.style:SetAlign(ALIGN.RIGHT)
    -- local session1PackPay = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackPay.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackPay, FONT_COLOR.DEFAULT)
    -- session1PackPay:SetText("Profit: 1591.40g")
    -- session1PackPay:AddAnchor("TOPRIGHT", session1, 0, 40)
    -- session1PackPay:SetAutoResize(true)
    -- session1PackPay.style:SetAlign(ALIGN.RIGHT)
    -- local session1PackProfit = wnd:CreateChildWidget("label", "title", 0, true)
    -- session1PackProfit.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session1PackProfit, FONT_COLOR.DEFAULT)
    -- session1PackProfit:SetText("1208.01g/hr, 1616 kills/hr ")
    -- session1PackProfit:AddAnchor("TOPRIGHT", session1, 0, 60)
    -- session1PackProfit:SetAutoResize(true)
    -- session1PackProfit.style:SetAlign(ALIGN.RIGHT)
    -- -- Session 2
    -- local session2 = wnd:CreateChildWidget("emptywidget", "session2", 0, true)
    -- session2:SetExtent(580, 70)
    -- local bg = session2:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    -- bg:SetColor(ConvertColor(11),ConvertColor(156),ConvertColor(35),0.3)
    -- bg:SetTextureInfo("bg_quest")
    -- bg:AddAnchor("TOPLEFT", session2, -10, -10)
    -- bg:AddAnchor("BOTTOMRIGHT", session2, 10, 10)
    -- bg:Show(true)
    -- session2:AddAnchor("TOPLEFT", session1, 0, 90)
    -- local session2Label = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2Label.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2Label, FONT_COLOR.DEFAULT)
    -- session2Label:SetText("Solzreed Peninsula Turn-in (11/13/2024)")
    -- session2Label:AddAnchor("TOPLEFT", session2, 0, 0)
    -- session2Label:SetAutoResize(true)
    -- session2Label.style:SetAlign(ALIGN.LEFT)
    -- local session2PaidLabel = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PaidLabel.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PaidLabel, FONT_COLOR.DEFAULT)
    -- session2PaidLabel:SetText("PAID!")
    -- session2PaidLabel:AddAnchor("TOPRIGHT", session2, 0, 0)
    -- session2PaidLabel:SetAutoResize(true)
    -- session2PaidLabel.style:SetAlign(ALIGN.RIGHT)
    -- local subItemIcon = CreateItemIconButton("subItemIcon", session2Label)
    -- subItemIcon:Show(true)
    -- F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    -- F_SLOT.SetIconBackGround(subItemIcon, "game/ui/icon/icon_item_1338.dds")
    -- subItemIcon:AddAnchor("TOPLEFT", session2Label, 0, 16)

    -- local session2PackAmt = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackAmt.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackAmt, FONT_COLOR.DEFAULT)
    -- session2PackAmt:SetText("Rokhala Aged Cheese x17 (Charcoal x1462)")
    -- session2PackAmt:AddAnchor("TOPLEFT", session2, 50, 40)
    -- session2PackAmt:SetAutoResize(true)
    -- session2PackAmt.style:SetAlign(ALIGN.LEFT)
    -- local session2PackLabor = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackLabor.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackLabor, FONT_COLOR.DEFAULT)
    -- session2PackLabor:SetText("Labor: 2652")
    -- session2PackLabor:AddAnchor("TOPRIGHT", session2, 0, 20)
    -- session2PackLabor:SetAutoResize(true)
    -- session2PackLabor.style:SetAlign(ALIGN.RIGHT)
    -- local session2PackPay = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackPay.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackPay, FONT_COLOR.DEFAULT)
    -- session2PackPay:SetText("Total: 2529.26g")
    -- session2PackPay:AddAnchor("TOPRIGHT", session2, 0, 40)
    -- session2PackPay:SetAutoResize(true)
    -- session2PackPay.style:SetAlign(ALIGN.RIGHT)
    -- local session2PackProfit = wnd:CreateChildWidget("label", "title", 0, true)
    -- session2PackProfit.style:SetFontSize(FONT_SIZE.LARGE)
    -- ApplyTextColor(session2PackProfit, FONT_COLOR.DEFAULT)
    -- session2PackProfit:SetText("Profit: 1937.23g")
    -- session2PackProfit:AddAnchor("TOPRIGHT", session2, 0, 60)
    -- session2PackProfit:SetAutoResize(true)
    -- session2PackProfit.style:SetAlign(ALIGN.RIGHT)

    return wnd
end 

local function CreateAccountingWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "accountingWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Accounting")
    title:AddAnchor("TOP", wnd, 0, 300)
    -- Session-holding Scroll List
    local sessionScrollList = W_CTRL.CreatePageScrollListCtrl("sessionScrollList", wnd)
    sessionScrollList:Show(true)
    sessionScrollList:AddAnchor("TOPLEFT", wnd, 4, 4)
    sessionScrollList:AddAnchor("BOTTOMRIGHT", wnd, -4, -4)
end

local function CreateUnderConstructionWindow(wndParent)
    local wnd = wndParent:CreateChildWidget("emptywidget", "commerceWindow", 0, true)
    wnd:SetExtent(600, 600)
    wnd:AddAnchor("TOP", wndParent, 0, 0)
    local title = wnd:CreateChildWidget("label", "title", 0, true)
    title:SetAutoResize(true)
    title:SetHeight(FONT_SIZE.XLARGE)
    title.style:SetAlign(ALIGN.CENTER)
    title.style:SetFontSize(FONT_SIZE.XLARGE)
    ApplyTextColor(title, FONT_COLOR.TITLE)
    title:SetText("Coming Soon - Under Construction")
    title:AddAnchor("TOP", wnd, 0, 300)
end 

local function OnLoad()
    packsAddon = require("your_paystub/packs")
    lootAddon = require("your_paystub/loot")
    accountingAddon = require("your_paystub/accounting")
    
    local tabInfo = {
        {
            validationCheckFunc = function()
                return true
            end,
            title = "Commerce",
            subWindowConstructor = function(parent)
                CreateCommerceWindow(parent)
            end
        },
        {
            validationCheckFunc = function()
                return true
            end,
            title = "Loot Tracker",
            subWindowConstructor = function(parent)
                CreateLootTrackerWindow(parent)
            end
        },
        {
            validationCheckFunc = function()
                return true
            end,
            title = "Recipe Profit",
            subWindowConstructor = function(parent)
                CreateUnderConstructionWindow(parent)
            end
        },
        {
            validationCheckFunc = function()
                return true
            end,
            title = "Plant Timers",
            subWindowConstructor = function(parent)
                CreateUnderConstructionWindow(parent)
            end
        },
        {
            validationCheckFunc = function()
                return true
            end,
            title = "Accounting",
            subWindowConstructor = function(parent)
                CreateAccountingWindow(parent)
            end
        }
    }
    -- Display Window
    paystubDisplayWindow = api.Interface:CreateWindow("paystubDisplayWindow", "Your Paystub", 600, 840, tabInfo)
    paystubDisplayWindow:AddAnchor("CENTER", "UIParent", 0, 0)
    paystubDisplayWindow:Show(false)

    -- Add button for opening the Your Paystub window
    local bagFrame = ADDON:GetContent(UIC.BAG)
    paystubBtn = bagFrame:CreateChildWidget("button", "paystubBtn", 0, true)
    paystubBtn:AddAnchor("BOTTOMLEFT", bagFrame.expandBtn, -55, 5)
    ApplyButtonSkin(paystubBtn, BUTTON_CONTENTS.CHARACTER_INFO_DETAIL)
    -- paystubBtn:SetText("Paystub")
    paystubBtn:SetExtent(50, 50)
    paystubBtn:Show(true)
    function paystubBtn:OnClick()
        if paystubDisplayWindow:IsVisible() then 
            --> this is where i'd clear the heavy RAM wise table
            paystubDisplayWindow:Show(false)
        else
            paystubDisplayWindow:Show(true)
        end 
    end 
    paystubBtn:SetHandler("OnClick", paystubBtn.OnClick)
    
    -- for key, value in pairs(bagFrame) do 
    --     api.Log:Info(key .. " " .. tostring(value))
    -- end 

    -- api.Interface:SetTooltipOnPos("Hello World", paystubDisplayWindow, 0, 0)

    packsAddon:OnLoad()
    lootAddon:OnLoad()
    accountingAddon:OnLoad()
    -- for key, value in pairs(getmetatable(paystubDisplayWindow.tab)) do 
    --     api.Log:Info(key .. " " .. tostring(value))
    -- end 
    -- for key, value in pairs(paystubDisplayWindow.tab) do 
    --     api.Log:Info(key .. " " .. tostring(value))
    -- end 
    -- paystubDisplayWindow.tab:ClearChildren()
    -- paystubDisplayWindow.tab:Show(false)
    -- paystubDisplayWindow.tab

    -- local itemInfo = api.Bag:GetBagItemInfo(1, 45)
    -- for i=1, 150 do 
    --     itemInfo = api.Bag:GetBagItemInfo(1, i)
    --     if itemInfo ~= nil then 
    --         api.Log:Info("#" .. tostring(i) .. " " .. itemInfo.name)
    --     end
        
    -- end 
    -- local itemInfo = api.Bag:GetBagItemInfo(1, 51)
    -- for key, value in pairs(itemInfo) do 
    --     api.Log:Info(key .. " " .. tostring(value))
    -- end 
    -- api.Map:ToggleMapWithPortal(323, 18841.77778 + 2480.0, 23335.1111, 43)

    api.Log:Info("[Your Paystub] Successfully loaded. Find the paystub window button in your inventory.")
end

local function OnUnload()
    packsAddon:OnUnload()
    packsAddon = nil
    lootAddon:OnUnload()
    lootAddon = nil
    accountingAddon:OnUnload()
    accountingAddon = nil
    paystubDisplayWindow:Show(false)
    paystubDisplayWindow = nil
    api.Interface:Free(paystubDisplayWindow)
    paystubBtn:Show(false)
    paystubBtn = nil
    api.Interface:Free(paystubBtn)
end

your_paystub_addon.OnLoad = OnLoad
your_paystub_addon.OnUnload = OnUnload

return your_paystub_addon
