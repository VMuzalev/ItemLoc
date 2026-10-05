-- ItemLoc: поиск предметов по названию на любом языке
local ADDON_NAME = ...

-- Если файл с данными не создан, аддон не падает, а подсказывает что делать
if not ItemLocData then
    ItemLocData = {}
    ItemLocLocales = ItemLocLocales or { "en" }
    ItemLocMissingData = true
end

local db = { strict = false }   -- настройки; при входе в игру заменятся на сохранённые

---------------------------------------------------------------------------
-- Вспомогательные функции
---------------------------------------------------------------------------
local function Print(msg)
    print("|cff33ff99ItemLoc:|r " .. msg)
end

-- Нижний регистр с поддержкой кириллицы и европейских букв (UTF-8)
local function utf8lower(s)
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end) -- А-П
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end) -- Р-Я
    s = s:gsub("\208\129", "\209\145")                                                           -- Ё
    s = s:gsub("\195([\128-\150\152-\158])", function(c) return "\195" .. string.char(c:byte() + 32) end) -- Ä Ö Ü É Ñ ...
    return s:lower()
end

-- Нижний регистр, обрезка пробелов по краям, одиночные пробелы внутри
local function normalize(s)
    s = utf8lower(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%s+", " ")
    return s
end

---------------------------------------------------------------------------
-- Поиск
-- strict = true : название на каком-либо языке должно совпасть полностью
-- strict = false: часть названия или все слова запроса в любом порядке
-- Оценка (меньше = лучше): 1 точное, 2 начинается с запроса,
--                          3 содержит запрос, 4 содержит все слова
---------------------------------------------------------------------------
local function Search(query, strict)
    local words = {}
    for w in query:gmatch("%S+") do words[#words + 1] = w end

    local results = {}
    for id, row in pairs(ItemLocData) do
        local low = row[2]
        local best
        for i = 1, #low do
            local name = low[i]
            if name ~= "" then
                local score
                if name == query then
                    score = 1
                elseif not strict then
                    if name:sub(1, #query) == query then
                        score = 2
                    elseif name:find(query, 1, true) then
                        score = 3
                    elseif #words > 1 then
                        local all = true
                        for _, w in ipairs(words) do
                            if not name:find(w, 1, true) then all = false break end
                        end
                        if all then score = 4 end
                    end
                end
                if score and (not best or score < best) then best = score end
            end
        end
        if best then results[#results + 1] = { id = id, score = best } end
    end

    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.id < b.id
    end)
    return results
end

---------------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Данные из игры: иконка, цвет качества, тип, уровень.
-- Иконка берётся мгновенно, остальное подгружается из кэша клиента асинхронно.
---------------------------------------------------------------------------
local GetInfo        = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestLoad    = C_Item and C_Item.RequestLoadItemDataByID
local QUESTION_ICON  = 134400

local function QualityHex(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x",
        math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function GetGameInfo(id)
    local info = {}
    if GetInfoInstant then
        local ok, _, _, _, equipLoc, icon = pcall(GetInfoInstant, id)
        if ok then info.equipLoc, info.icon = equipLoc, icon end
    end
    if GetInfo then
        local ok, name, link, quality, ilvl, minLevel, itype, subtype, _, equipLoc, icon = pcall(GetInfo, id)
        if ok and type(name) == "string" then
            info.name, info.link, info.quality = name, link, quality
            info.ilvl, info.minLevel = ilvl, minLevel
            info.type, info.subtype = itype, subtype
            info.equipLoc = equipLoc or info.equipLoc
            info.icon = icon or info.icon
        end
    end
    return info
end

local ROW_H = math.max(56, (#ItemLocLocales + 2) * 13 + 10)
local MAX_ROWS = math.max(3, math.floor(400 / ROW_H))
local FRAME_W = 560

local frame = CreateFrame("Frame", "ItemLocFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(FRAME_W, 160 + MAX_ROWS * ROW_H)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "ItemLocFrame")   -- закрытие по Esc

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("ItemLoc: поиск предметов")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -6, -6)

local edit = CreateFrame("EditBox", "ItemLocEditBox", frame, "InputBoxTemplate")
edit:SetSize(400, 22)
edit:SetPoint("TOPLEFT", 30, -48)
edit:SetAutoFocus(false)
edit:SetMaxLetters(120)

local searchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchBtn:SetSize(90, 24)
searchBtn:SetPoint("LEFT", edit, "RIGHT", 10, 0)
searchBtn:SetText("Найти")

local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
modeBtn:SetSize(190, 24)
modeBtn:SetPoint("TOPLEFT", 24, -78)

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("LEFT", modeBtn, "RIGHT", 12, 0)
status:SetWidth(FRAME_W - 260)
status:SetJustifyH("LEFT")

local function UpdateModeText()
    modeBtn:SetText(db.strict and "Режим: строгий" or "Режим: нестрогий")
end

-- Строки результатов
local rows = {}
for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(FRAME_W - 48, ROW_H)
    row:SetPoint("TOPLEFT", 24, -(110 + (i - 1) * ROW_H))
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("TOPLEFT", 6, -6)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 54, -6)
    row.text:SetWidth(FRAME_W - 48 - 64)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
        if self.link then
            GameTooltip:AddLine("Shift+клик: вставить ссылку в чат", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
    end)
    row:Hide()
    rows[i] = row
end

-- Заполняет строку: иконка, название из игры, тип, названия на всех языках.
-- Возвращает true, если данные из игры уже есть.
local function FillRow(row)
    local id = row.id
    if not id then return true end
    local g = GetGameInfo(id)
    local names = ItemLocData[id][1]

    local firstName = ""
    for j = 1, #names do
        if names[j] and names[j] ~= "" then firstName = names[j] break end
    end

    row.icon:SetTexture(g.icon or QUESTION_ICON)
    row.link = g.link

    local title = g.name and (QualityHex(g.quality) .. g.name .. "|r") or firstName
    local lines = { title .. "  |cff888888ID " .. id .. "|r" }

    if g.name then
        local meta = {}
        if g.type and g.type ~= "" then meta[#meta + 1] = g.type end
        if g.subtype and g.subtype ~= "" and g.subtype ~= g.type then meta[#meta + 1] = g.subtype end
        local slot = g.equipLoc and g.equipLoc ~= "" and _G[g.equipLoc]
        if slot then meta[#meta + 1] = slot end
        if g.ilvl and g.ilvl > 0 then meta[#meta + 1] = "iLvl " .. g.ilvl end
        if g.minLevel and g.minLevel > 0 then meta[#meta + 1] = "треб. ур. " .. g.minLevel end
        lines[2] = "|cffbbbbbb" .. table.concat(meta, ", ") .. "|r"
    elseif row.failed then
        lines[2] = "|cffff8080игра не знает этот предмет (нет данных в клиенте)|r"
    else
        lines[2] = "|cff888888загрузка данных из игры...|r"
    end

    for j = 1, #ItemLocLocales do
        if names[j] and names[j] ~= "" then
            lines[#lines + 1] = "|cffaaaaaa" .. ItemLocLocales[j] .. ":|r " .. names[j]
        end
    end
    row.text:SetText(table.concat(lines, "\n"))
    return g.name ~= nil
end

---------------------------------------------------------------------------
-- Постраничный просмотр
---------------------------------------------------------------------------
local currentResults, page = {}, 1

local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageText:SetPoint("BOTTOM", 0, 24)
pageText:SetWidth(140)

local prevBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
prevBtn:SetSize(44, 22)
prevBtn:SetPoint("RIGHT", pageText, "LEFT", -8, 0)
prevBtn:SetText("<")

local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
nextBtn:SetSize(44, 22)
nextBtn:SetPoint("LEFT", pageText, "RIGHT", 8, 0)
nextBtn:SetText(">")

local function ShowPage()
    local total = #currentResults
    local pages = math.max(1, math.ceil(total / MAX_ROWS))
    page = math.min(math.max(page, 1), pages)
    local first = (page - 1) * MAX_ROWS

    for i = 1, MAX_ROWS do
        local row, r = rows[i], currentResults[first + i]
        if r then
            row.id = r.id
            row.failed = false
            row.link = nil
            if not FillRow(row) and RequestLoad then
                RequestLoad(r.id)   -- результат придёт в GET_ITEM_INFO_RECEIVED
            end
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end

    if total == 0 then
        pageText:SetText("")
        status:SetText("Ничего не найдено")
    else
        pageText:SetText("Стр. " .. page .. " из " .. pages)
        status:SetText("Найдено: " .. total)
    end
    if page > 1 then prevBtn:Enable() else prevBtn:Disable() end
    if page < pages then nextBtn:Enable() else nextBtn:Disable() end
end

local function ShowResults(results)
    currentResults = results
    page = 1
    ShowPage()
end

local function GoToPage(delta, toEdge)
    local pages = math.max(1, math.ceil(#currentResults / MAX_ROWS))
    if toEdge then
        page = delta < 0 and 1 or pages
    else
        page = page + delta
    end
    ShowPage()
end

prevBtn:SetScript("OnClick", function() GoToPage(-1, IsShiftKeyDown()) end)
nextBtn:SetScript("OnClick", function() GoToPage(1, IsShiftKeyDown()) end)
for _, b in ipairs({ prevBtn, nextBtn }) do
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Shift+клик: в начало / в конец", 1, 1, 1)
        GameTooltip:AddLine("Также можно листать колесом мыши", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(_, delta) GoToPage(-delta) end)

local function DoSearch()
    if ItemLocMissingData then
        status:SetText("Нет файла LocalizationData.lua, см. README")
        return
    end
    local q = normalize(edit:GetText())
    if q == "" then
        ShowResults({})
        status:SetText("Введите название предмета")
        return
    end
    ShowResults(Search(q, db.strict))
end

edit:SetScript("OnEnterPressed", DoSearch)
edit:SetScript("OnEscapePressed", edit.ClearFocus)
searchBtn:SetScript("OnClick", DoSearch)
modeBtn:SetScript("OnClick", function()
    db.strict = not db.strict
    UpdateModeText()
    if edit:GetText() ~= "" then DoSearch() end
end)
modeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Режим поиска", 1, 1, 1)
    GameTooltip:AddLine("Строгий: название должно совпасть полностью (на любом языке).", nil, nil, nil, true)
    GameTooltip:AddLine("Нестрогий: часть названия или слова в любом порядке.", nil, nil, nil, true)
    GameTooltip:Show()
end)
modeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
frame:SetScript("OnShow", function() edit:SetFocus() end)

---------------------------------------------------------------------------
-- Загрузка настроек и команды
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Проверка версии клиента: сообщаем, если игра обновилась, а база старая
---------------------------------------------------------------------------
local function ClientBuild()
    local _, build, _, toc = GetBuildInfo()
    return tostring(build or "?"), toc
end

local function DataBuild()
    return ItemLocDataBuild and tostring(ItemLocDataBuild):match("(%d+)$")
end

local function CheckClientBuild()
    local client = ClientBuild()
    if db.lastBuild == client then return end   -- об этой сборке уже сообщали
    db.lastBuild = client
    local data = DataBuild()
    if data == client then return end
    if data then
        Print("клиент игры обновился (сборка " .. client .. "), а база названий собрана для сборки "
            .. data .. ". Если какие-то предметы не находятся, обновите базу: python tools/build_data.py. "
            .. "Подробности: /il info")
    else
        Print("в файле данных нет метки сборки. Пересоберите базу: python tools/build_data.py. "
            .. "Подробности: /il info")
    end
end

local function PrintInfo()
    local client, toc = ClientBuild()
    local count = 0
    for _ in pairs(ItemLocData) do count = count + 1 end
    Print("клиент: сборка " .. client .. ", Interface " .. tostring(toc))
    Print("база: " .. count .. " предметов, собрана для сборки " .. (ItemLocDataBuild or "неизвестно"))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ItemLocDB = ItemLocDB or { strict = false }
        db = ItemLocDB
        UpdateModeText()
    elseif event == "PLAYER_LOGIN" then
        -- небольшая пауза, чтобы сообщение не потерялось среди других при входе
        if C_Timer and C_Timer.After then C_Timer.After(4, CheckClientBuild) else CheckClientBuild() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        for i = 1, MAX_ROWS do
            local row = rows[i]
            if row.id and row.id == arg1 then
                row.failed = (arg2 == false)
                FillRow(row)
            end
        end
    end
end)
UpdateModeText()

SLASH_ITEMLOC1 = "/il"
SLASH_ITEMLOC2 = "/itemloc"
SlashCmdList["ITEMLOC"] = function(msg)
    if msg == "info" then PrintInfo() return end
    if msg and msg ~= "" then
        frame:Show()
        edit:SetText(msg)
        DoSearch()
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end