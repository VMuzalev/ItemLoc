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
local ROW_H = (#ItemLocLocales + 1) * 13 + 8
local MAX_ROWS = math.max(3, math.floor(340 / ROW_H))
local FRAME_W = 560

local frame = CreateFrame("Frame", "ItemLocFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(FRAME_W, 120 + MAX_ROWS * ROW_H)
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
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 6, -4)
    row.text:SetWidth(FRAME_W - 64)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
    rows[i] = row
end

local function ShowResults(results)
    for i = 1, MAX_ROWS do
        local row, r = rows[i], results[i]
        if r then
            local names = ItemLocData[r.id][1]
            local lines = { "|cff00ff00ID " .. r.id .. "|r" }
            for j = 1, #ItemLocLocales do
                if names[j] and names[j] ~= "" then
                    lines[#lines + 1] = "|cffaaaaaa" .. ItemLocLocales[j] .. ":|r " .. names[j]
                end
            end
            row.id = r.id
            row.text:SetText(table.concat(lines, "\n"))
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end

    if #results == 0 then
        status:SetText("Ничего не найдено")
    elseif #results > MAX_ROWS then
        status:SetText("Найдено: " .. #results .. ". Показаны первые " .. MAX_ROWS .. ", уточните запрос")
    else
        status:SetText("Найдено: " .. #results)
    end
end

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
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON_NAME then return end
    ItemLocDB = ItemLocDB or { strict = false }
    db = ItemLocDB
    UpdateModeText()
end)
UpdateModeText()

SLASH_ITEMLOC1 = "/il"
SLASH_ITEMLOC2 = "/itemloc"
SlashCmdList["ITEMLOC"] = function(msg)
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
