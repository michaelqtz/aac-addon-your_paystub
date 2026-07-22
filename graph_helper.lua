--- Bar + trend-line chart helper for Your Paystub.
--
-- Ported from the game client's own market price chart
-- (game/scripts/x2ui/auction/market_price.lua), which draws its diagonal
-- price line and its trading-volume bars using a single "line" widget per
-- series: SetPoints({{beginX=,beginY=,endX=,endY=}, ...}) plus
-- SetLineColor/SetLineThickness/ClearPoints. A bar is just a point whose
-- begin/end share an X (a vertical stick), drawn extra-thick -- and ALL
-- bars of one color share ONE "line" widget/one SetPoints call, exactly
-- like market_price.lua's single volumeLine draws all 14 volume bars at
-- once. (An earlier version of this file created a separate "line" widget
-- per bar; positive-gain bars silently failed to render, most likely from
-- stacking many overlapping full-size "line" widgets rather than matching
-- the source material's one-widget-per-series structure.)
--
-- Y axis runs bottom-up (Y = 0 at the bottom of the chart, increasing
-- toward the top) -- confirmed by market_price.lua's own GetPositionY,
-- which maps value=0 -> Y=0 and value=maxValue -> Y=chartHeight with no
-- inversion anywhere in that file.
local graph_helper = {}

local function ConvertColor(c) return c / 255 end

graph_helper.COLOR = {
    GAIN     = {ConvertColor(41),  ConvertColor(190), ConvertColor(90),  0.7},
    LOSS     = {ConvertColor(210), ConvertColor(70),  ConvertColor(60),  0.7},
    TREND    = {ConvertColor(226), ConvertColor(130), ConvertColor(27),  1},
    GRIDLINE = {ConvertColor(188), ConvertColor(171), ConvertColor(138), 0.35},
}

-- Bottom strip of the widget reserved for date labels, so they never need
-- to be anchored outside the widget's own declared height.
local LABEL_STRIP_HEIGHT = 16

-- Any day with an actual gain/loss still gets at least this tall a bar,
-- even if sqrt-scaling would otherwise round it down to a sliver next to a
-- much bigger day -- a real (non-zero) change should never look identical
-- to a day where nothing happened at all.
local MIN_BAR_HEIGHT = 6

local function FormatGold(copperAmount)
    copperAmount = copperAmount or 0
    local sign = copperAmount < 0 and "-" or ""
    local val = math.floor(math.abs(copperAmount))
    local gold = math.floor(val / 10000)
    local silver = math.floor((val % 10000) / 100)
    return string.format("%s%d.%02dg", sign, gold, silver)
end

local function CreateHLine(widget, width, yOffset, color)
    local line = widget:CreateColorDrawable(color[1], color[2], color[3], color[4], "background")
    line:SetExtent(width, 1)
    line:AddAnchor("LEFT", widget, 0, yOffset)
    return line
end

--- Creates the chart container: top/bottom horizontal gridlines, two shared
--- "line" widgets (one per bar color, both growing up from the bottom
--- edge) and one for the trend line, and the three date labels
--- (start/middle/end). Per-day vertical gridlines and hover hit-areas are
--- (re)built in SetChartData since the day count varies.
function graph_helper:CreateBarLineChart(parent, id, width, height)
    local widget = parent:CreateChildWidget("emptywidget", id, 0, true)
    widget:SetExtent(width, height)
    widget:AddAnchor("TOPLEFT", parent, 0, 0)

    local plotHeight = height - LABEL_STRIP_HEIGHT
    widget.plotHeight = plotHeight

    widget.topGridline = CreateHLine(widget, width, 0, graph_helper.COLOR.GRIDLINE)
    widget.bottomGridline = CreateHLine(widget, width, plotHeight, graph_helper.COLOR.GRIDLINE)

    local gainBarsLine = widget:CreateChildWidget("line", "gainBarsLine", 0, true)
    gainBarsLine:SetLineColor(unpack(graph_helper.COLOR.GAIN))
    gainBarsLine:AddAnchor("TOPLEFT", widget, 0, 0)
    gainBarsLine:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    widget.gainBarsLine = gainBarsLine

    local lossBarsLine = widget:CreateChildWidget("line", "lossBarsLine", 0, true)
    lossBarsLine:SetLineColor(unpack(graph_helper.COLOR.LOSS))
    lossBarsLine:AddAnchor("TOPLEFT", widget, 0, 0)
    lossBarsLine:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    widget.lossBarsLine = lossBarsLine

    local trendLine = widget:CreateChildWidget("line", "trendLine", 0, true)
    trendLine:SetLineColor(unpack(graph_helper.COLOR.TREND))
    trendLine:SetLineThickness(4)
    trendLine:AddAnchor("TOPLEFT", widget, 0, 0)
    trendLine:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    widget.trendLine = trendLine

    -- These are pure decoration; don't let them intercept hover so the
    -- per-day hit-areas created in SetChartData reliably get OnEnter/OnLeave.
    for _, line in ipairs({gainBarsLine, lossBarsLine, trendLine}) do
        if line.EnableHitTest then line:EnableHitTest(false) end
    end

    widget.vGridlines = {}
    widget.hitAreas = {}
    widget.entries = {}

    local startLabel = widget:CreateChildWidget("label", "startLabel", 0, true)
    startLabel:SetAutoResize(true)
    startLabel:SetHeight(LABEL_STRIP_HEIGHT)
    startLabel.style:SetFontSize(FONT_SIZE.SMALL)
    startLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(startLabel, FONT_COLOR.DEFAULT)
    startLabel:AddAnchor("TOPLEFT", widget, 0, plotHeight + 11)
    widget.startLabel = startLabel

    local midLabel = widget:CreateChildWidget("label", "midLabel", 0, true)
    midLabel:SetAutoResize(true)
    midLabel:SetHeight(LABEL_STRIP_HEIGHT)
    midLabel.style:SetFontSize(FONT_SIZE.SMALL)
    midLabel.style:SetAlign(ALIGN.CENTER)
    ApplyTextColor(midLabel, FONT_COLOR.DEFAULT)
    midLabel:AddAnchor("TOP", widget, 0, plotHeight + 11)
    widget.midLabel = midLabel

    local endLabel = widget:CreateChildWidget("label", "endLabel", 0, true)
    endLabel:SetAutoResize(true)
    endLabel:SetHeight(LABEL_STRIP_HEIGHT)
    endLabel.style:SetFontSize(FONT_SIZE.SMALL)
    endLabel.style:SetAlign(ALIGN.RIGHT)
    ApplyTextColor(endLabel, FONT_COLOR.DEFAULT)
    endLabel:AddAnchor("TOPRIGHT", widget, 0, plotHeight + 11)
    widget.endLabel = endLabel

    return widget
end

-- Tooltip always anchors just below the whole chart (not per-day), per user
-- request -- using the chart widget's own offset/height rather than the
-- hovered hit-area's, since anchoring off a hit-area placed it at the top
-- of the window instead.
local function GetTooltipAnchor(widget)
    local posX, posY = widget:GetOffset()
    return posX, posY + widget:GetHeight() + 8
end

local function ShowDayTooltip(widget, hitArea, index)
    local entry = widget.entries[index]
    if entry == nil then return end

    local dateStr = "Unknown Date"
    local date = api.Time:TimeToDate(entry.endTimestamp)
    if date ~= nil then
        dateStr = string.format("%02d/%02d/%04d", date.month, date.day, date.year)
    end

    local net = entry.netGold or 0
    local netLabel = net >= 0 and "Gain: " or "Loss: "
    local text = dateStr .. "\n" .. netLabel .. FormatGold(net) .. "\nOverall Gold: " .. FormatGold(entry.totalGold or 0)

    if entry.details ~= nil then
        for _, d in ipairs(entry.details) do
            if (d.amount or 0) > 0 then
                text = text .. "\n" .. d.label .. ": " .. FormatGold(d.amount)
            end
        end
    end

    local posX, posY = GetTooltipAnchor(widget)
    api.Interface:SetTooltipOnPos(text, widget, posX, posY)
end

local function HideDayTooltip(widget)
    local posX, posY = GetTooltipAnchor(widget)
    api.Interface:SetTooltipOnPos(nil, widget, posX, posY)
end

--- entries: array of { netGold = <copper delta, may be negative>, totalGold = <copper total>,
--- endTimestamp = <api.Time timestamp for this day> }, ordered oldest first (left) to most
--- recent (right). dateLabels: optional { start = str, mid = str, [end] = str }.
function graph_helper:SetChartData(widget, entries, dateLabels)
    local width = widget:GetWidth()
    local plotHeight = widget.plotHeight
    if width <= 0 or plotHeight <= 0 then return end

    widget.entries = entries or {}

    for _, gridline in ipairs(widget.vGridlines) do gridline:Show(false) end
    for _, hitArea in ipairs(widget.hitAreas) do hitArea:Show(false) end

    if entries == nil or #entries == 0 then
        widget.trendLine:ClearPoints()
        widget.gainBarsLine:ClearPoints()
        widget.lossBarsLine:ClearPoints()
        widget.startLabel:SetText("")
        widget.midLabel:SetText("")
        widget.endLabel:SetText("")
        return
    end

    if dateLabels ~= nil then
        widget.startLabel:SetText(dateLabels.start or "")
        widget.midLabel:SetText(dateLabels.mid or "")
        widget.endLabel:SetText(dateLabels["end"] or "")
    end

    local columnWidth = width / #entries
    local barWidth = math.max(columnWidth * 0.5, 2)
    local margin = 4

    widget.gainBarsLine:SetLineThickness(barWidth)
    widget.lossBarsLine:SetLineThickness(barWidth)

    local maxNet = 1
    local minTotal, maxTotal = nil, nil
    for _, e in ipairs(entries) do
        maxNet = math.max(maxNet, math.abs(e.netGold or 0))
        local total = e.totalGold or 0
        if minTotal == nil or total < minTotal then minTotal = total end
        if maxTotal == nil or total > maxTotal then maxTotal = total end
    end
    if minTotal == nil then minTotal = 0 end
    if maxTotal == nil or maxTotal == minTotal then maxTotal = minTotal + 1 end

    local gainPoints, lossPoints, trendPoints = {}, {}, {}

    for i, e in ipairs(entries) do
        local centerX = columnWidth * (i - 1) + columnWidth / 2

        -- Per-day vertical gridline (lazily created/reused).
        local gridline = widget.vGridlines[i]
        if gridline == nil then
            local c = graph_helper.COLOR.GRIDLINE
            gridline = widget:CreateColorDrawable(c[1], c[2], c[3], c[4], "background")
            widget.vGridlines[i] = gridline
        end
        gridline:Show(true)
        gridline:SetExtent(1, plotHeight)
        gridline:RemoveAllAnchors()
        gridline:AddAnchor("TOPLEFT", widget, columnWidth * (i - 1), 0)

        -- Bar: one vertical "stick" from the bottom baseline, grouped into
        -- the shared gain/loss line widget by sign -- magnitude only (a
        -- negative day is just as tall as a same-sized positive one, only
        -- red instead of green), same as market_price.lua's own volume
        -- bars, which always grow up from a single Y=0 baseline. Square-root
        -- scale: a middle ground between linear (a single huge outlier day
        -- flattens every ordinary day to invisible) and log (a 10g day and
        -- a 100,000g day end up looking almost the same height). sqrt
        -- compresses the huge/rare values without erasing the difference
        -- between two more ordinary-but-still-quite-different amounts.
        local net = e.netGold or 0
        local barHeight = (math.sqrt(math.abs(net)) / math.sqrt(maxNet)) * (plotHeight - margin)
        if net ~= 0 and barHeight < MIN_BAR_HEIGHT then
            barHeight = MIN_BAR_HEIGHT
        end
        local segment = {
            beginX = centerX, beginY = 0,
            endX   = centerX, endY   = barHeight,
        }
        if net >= 0 then
            table.insert(gainPoints, segment)
        else
            table.insert(lossPoints, segment)
        end

        -- Trend point: overall gold scaled across the plot height,
        -- Y = 0 at bottom (see file header note on this widget's Y axis).
        local total = e.totalGold or 0
        local normalized = (total - minTotal) / (maxTotal - minTotal)
        table.insert(trendPoints, {x = centerX, y = margin + normalized * (plotHeight - margin * 2)})

        -- Hover hit-area (lazily created/reused). The highlight background
        -- darkens automatically on hover via the button's native
        -- highlight-state -- no manual show/hide needed for that part.
        local hitArea = widget.hitAreas[i]
        if hitArea == nil then
            hitArea = widget:CreateChildWidget("button", "hitArea", i, true)
            local blankBg = hitArea:CreateColorDrawable(0, 0, 0, 0, "background")
            local highlightBg = hitArea:CreateColorDrawable(0, 0, 0, 0.25, "background")
            hitArea:SetNormalBackground(blankBg)
            hitArea:SetPushedBackground(highlightBg)
            hitArea:SetHighlightBackground(highlightBg)
            hitArea:SetDisabledBackground(blankBg)
            widget.hitAreas[i] = hitArea

            function hitArea:OnEnter()
                ShowDayTooltip(widget, hitArea, i)
            end
            hitArea:SetHandler("OnEnter", hitArea.OnEnter)

            function hitArea:OnLeave()
                HideDayTooltip(widget)
            end
            hitArea:SetHandler("OnLeave", hitArea.OnLeave)
        end
        hitArea:Show(true)
        hitArea:SetExtent(columnWidth, plotHeight)
        hitArea:RemoveAllAnchors()
        hitArea:AddAnchor("TOPLEFT", widget, columnWidth * (i - 1), 0)
    end

    widget.gainBarsLine:ClearPoints()
    widget.gainBarsLine:SetPoints(gainPoints)
    widget.lossBarsLine:ClearPoints()
    widget.lossBarsLine:SetPoints(lossPoints)

    local linePoints = {}
    for i = 1, #trendPoints - 1 do
        linePoints[i] = {
            beginX = trendPoints[i].x,     beginY = trendPoints[i].y,
            endX   = trendPoints[i + 1].x, endY   = trendPoints[i + 1].y,
        }
    end
    widget.trendLine:ClearPoints()
    widget.trendLine:SetPoints(linePoints)
end

--- Small colored-swatch + label, for a legend under the chart.
function graph_helper:CreateLegendItem(parent, id, text, color)
    local item = parent:CreateChildWidget("emptywidget", id, 0, true)

    local swatch = item:CreateColorDrawable(color[1], color[2], color[3], color[4], "background")
    swatch:SetExtent(12, 12)
    swatch:AddAnchor("LEFT", item, 0, 0)

    local label = item:CreateChildWidget("label", "label", 0, true)
    label:SetAutoResize(true)
    label:SetHeight(FONT_SIZE.SMALL)
    label:AddAnchor("LEFT", swatch, "RIGHT", 5, 0)
    label:SetText(text)
    ApplyTextColor(label, FONT_COLOR.DEFAULT)

    item:SetExtent(12 + 5 + label:GetWidth(), 12)
    return item
end

return graph_helper
