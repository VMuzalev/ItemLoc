-- ItemLoc: поиск предметов по названию на любом языке
-- Данные каждого языка лежат в отдельном модуле ItemLoc_<локаль> (LoadOnDemand)
-- и загружаются только для языков, выбранных в настройках. Английский всегда включён.
local ADDON_NAME = ...

-- ItemLocData[локаль] = { n = {[id] = название}, l = {[id] = название в нижнем регистре} }
ItemLocData = ItemLocData or {}

local LOCALES = {
    { "enUS", "English" },
    { "ruRU", "Русский" },
    { "deDE", "Deutsch" },
    { "frFR", "Français" },
    { "esES", "Español (España)" },
    { "esMX", "Español (México)" },
    { "itIT", "Italiano" },
    { "ptBR", "Português (Brasil)" },
    { "koKR", "Korean" },
    { "zhCN", "Chinese (Simplified)" },
    { "zhTW", "Chinese (Traditional)" },
}

local db = { strict = false, langs = {} }   -- при входе в игру заменится на сохранённые настройки
local loadReason = {}                        -- локаль -> почему модуль не загрузился

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
-- Языки: какие включены и загрузка модулей по требованию
---------------------------------------------------------------------------
-- Английский всегда первый, затем выбранные языки в порядке списка LOCALES
local function ActiveLocales()
    local list = { "enUS" }
    for _, info in ipairs(LOCALES) do
        local loc = info[1]
        if loc ~= "enUS" and db.langs[loc] then list[#list + 1] = loc end
    end
    return list
end

-- Подгружает модуль языка, если он ещё не загружен. true, если данные есть.
local function EnsureLocale(loc)
    if ItemLocData[loc] then return true end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then
        local ok, loaded, reason = pcall(load, "ItemLoc_" .. loc)
        if ok and not loaded then loadReason[loc] = reason end
    end
    return ItemLocData[loc] ~= nil
end

-- Загружает все включённые языки. Возвращает список тех, что загрузить не удалось.
local function EnsureActive()
    local missing = {}
    for _, loc in ipairs(ActiveLocales()) do
        if not EnsureLocale(loc) then missing[#missing + 1] = loc end
    end
    return missing
end

---------------------------------------------------------------------------
-- Поиск
-- strict = true : название на каком-либо включённом языке должно совпасть полностью
-- strict = false: часть названия или все слова запроса в любом порядке
-- Оценка (меньше = лучше): 1 точное, 2 начинается с запроса,
--                          3 содержит запрос, 4 содержит все слова
---------------------------------------------------------------------------
local function Search(query, strict)
    local words = {}
    for w in query:gmatch("%S+") do words[#words + 1] = w end

    local best = {}   -- id -> лучшая оценка среди всех языков
    for _, loc in ipairs(ActiveLocales()) do
        local d = ItemLocData[loc]
        if d then
            for id, name in pairs(d.l) do
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
                if score and (not best[id] or score < best[id]) then best[id] = score end
            end
        end
    end

    local results = {}
    for id, score in pairs(best) do results[#results + 1] = { id = id, score = score } end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.id < b.id
    end)
    return results
end

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

---------------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------------
local FRAME_W = 560
local BODY_H = 380        -- высота области результатов
local ROWS_COUNT = 7      -- сколько строк создано; сколько показано, зависит от числа языков

local frame = CreateFrame("Frame", "ItemLocFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(FRAME_W, 160 + BODY_H)
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
modeBtn:SetSize(170, 24)
modeBtn:SetPoint("TOPLEFT", 24, -78)

local langBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
langBtn:SetSize(100, 24)
langBtn:SetPoint("LEFT", modeBtn, "RIGHT", 8, 0)
langBtn:SetText("Языки...")

local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("LEFT", langBtn, "RIGHT", 12, 0)
status:SetWidth(FRAME_W - 24 - 170 - 8 - 100 - 12 - 28)
status:SetJustifyH("LEFT")

local function UpdateModeText()
    modeBtn:SetText(db.strict and "Режим: строгий" or "Режим: нестрогий")
end

-- Строки результатов (высота и положение задаются в Layout)
local rows = {}
for i = 1, ROWS_COUNT do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(FRAME_W - 48, 56)
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

-- Высота строки зависит от числа включённых языков, от неё зависит число строк на странице
local rowH, perPage = 56, 6
local function Layout()
    local n = #ActiveLocales()
    rowH = math.max(56, (n + 2) * 13 + 10)
    perPage = math.max(1, math.min(ROWS_COUNT, math.floor(BODY_H / rowH)))
    for i = 1, ROWS_COUNT do
        local row = rows[i]
        row:SetHeight(rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 24, -(110 + (i - 1) * rowH))
    end
end

---------------------------------------------------------------------------
-- Постраничный просмотр
---------------------------------------------------------------------------
local currentResults, page = {}, 1
local statusExtra = ""   -- дописывается к строке состояния (например, нет данных для языка)

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

-- Заполняет строку: иконка, название из игры, тип, названия на включённых языках.
-- Возвращает true, если данные из игры уже есть.
local function FillRow(row)
    local id = row.id
    if not id then return true end
    local g = GetGameInfo(id)

    local names = {}   -- { {локаль, название}, ... } только по включённым языкам
    for _, loc in ipairs(ActiveLocales()) do
        local d = ItemLocData[loc]
        local nm = d and d.n[id]
        if nm and nm ~= "" then names[#names + 1] = { loc, nm } end
    end

    row.icon:SetTexture(g.icon or QUESTION_ICON)
    row.link = g.link

    local title = g.name and (QualityHex(g.quality) .. g.name .. "|r") or (names[1] and names[1][2]) or ""
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

    for _, pair in ipairs(names) do
        lines[#lines + 1] = "|cffaaaaaa" .. pair[1] .. ":|r " .. pair[2]
    end
    row.text:SetText(table.concat(lines, "\n"))
    return g.name ~= nil
end

local function ShowPage()
    Layout()
    local total = #currentResults
    local pages = math.max(1, math.ceil(total / perPage))
    page = math.min(math.max(page, 1), pages)
    local first = (page - 1) * perPage

    for i = 1, ROWS_COUNT do
        local row = rows[i]
        local r = (i <= perPage) and currentResults[first + i] or nil
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
        status:SetText("Ничего не найдено" .. statusExtra)
    else
        pageText:SetText("Стр. " .. page .. " из " .. pages)
        status:SetText("Найдено: " .. total .. statusExtra)
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
    local pages = math.max(1, math.ceil(#currentResults / perPage))
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

---------------------------------------------------------------------------
-- Поиск из окна
---------------------------------------------------------------------------
local function DoSearch()
    local missing = EnsureActive()
    statusExtra = ""
    if not ItemLocData.enUS then
        ShowResults({})
        status:SetText("|cffff8080Не найден модуль ItemLoc_enUS. Переустановите аддон: нужны все папки ItemLoc*|r")
        return
    end
    if #missing > 0 then
        statusExtra = "  |cffff8080Нет данных: " .. table.concat(missing, ", ") .. "|r"
    end

    local q = normalize(edit:GetText())
    if q == "" then
        ShowResults({})
        status:SetText("Введите название предмета" .. statusExtra)
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
    GameTooltip:AddLine("Строгий: название должно совпасть полностью (на любом включённом языке).", nil, nil, nil, true)
    GameTooltip:AddLine("Нестрогий: часть названия или слова в любом порядке.", nil, nil, nil, true)
    GameTooltip:Show()
end)
modeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- При открытии окна сразу подгружаем данные включённых языков (один раз за сессию)
frame:SetScript("OnShow", function()
    edit:SetFocus()
    EnsureActive()
end)

---------------------------------------------------------------------------
-- Настройки: выбор языков
---------------------------------------------------------------------------
local OpenOptions = function() Print("настройки недоступны в этой версии клиента") end

local panel = CreateFrame("Frame", "ItemLocOptionsPanel")
panel.name = "ItemLoc"

local pTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
pTitle:SetPoint("TOPLEFT", 16, -16)
pTitle:SetText("ItemLoc: языки поиска")

local pHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
pHelp:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", 0, -8)
pHelp:SetWidth(540)
pHelp:SetJustifyH("LEFT")
pHelp:SetText("Английский используется всегда. Отметьте дополнительные языки: данные загружаются только "
    .. "для выбранных языков, при первом открытии окна поиска. Если снять галочку, язык перестанет "
    .. "участвовать в поиске, а память освободится после /reload.")

local checks, statuses = {}, {}

local function RefreshPanel()
    for _, info in ipairs(LOCALES) do
        local loc = info[1]
        local enabled = (loc == "enUS") or db.langs[loc] == true
        checks[loc]:SetChecked(enabled)
        local d = ItemLocData[loc]
        local text = ""
        if d and d.empty then
            text = "|cff888888нет данных для этой версии игры|r"
        elseif d then
            text = enabled and "|cff00ff00загружен|r" or "|cff888888загружен до /reload|r"
        elseif enabled then
            text = "|cffff8080не найден: папка ItemLoc_" .. loc .. (loadReason[loc] and (" (" .. tostring(loadReason[loc]) .. ")") or "") .. "|r"
        end
        statuses[loc]:SetText(text)
    end
end

for i, info in ipairs(LOCALES) do
    local loc, label = info[1], info[2]
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", pHelp, "BOTTOMLEFT", 0, -10 - (i - 1) * 28)
    local text = panel:CreateFontString(nil, "ARTWORK", loc == "enUS" and "GameFontDisable" or "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label .. " (" .. loc .. ")")
    local st = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    st:SetPoint("LEFT", cb, "RIGHT", 230, 0)
    st:SetJustifyH("LEFT")
    if loc == "enUS" then
        cb:SetChecked(true)
        cb:Disable()
    else
        cb:SetScript("OnClick", function(self)
            db.langs[loc] = self:GetChecked() and true or nil
            if db.langs[loc] then EnsureLocale(loc) end
            RefreshPanel()
            if frame:IsShown() and edit:GetText() ~= "" then DoSearch() end
        end)
    end
    checks[loc], statuses[loc] = cb, st
end
panel:SetScript("OnShow", RefreshPanel)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
    if ok and category then
        Settings.RegisterAddOnCategory(category)
        OpenOptions = function() pcall(Settings.OpenToCategory, category:GetID()) end
    end
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    OpenOptions = function()
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)   -- известная особенность: с первого раза открывается не та вкладка
    end
end
langBtn:SetScript("OnClick", function() OpenOptions() end)

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
            .. data .. ". Если какие-то предметы не находятся, обновите аддон (CurseForge или GitHub): "
            .. "новая база выходит автоматически. Подробности: /il info")
    else
        Print("в аддоне нет метки сборки базы. Обновите аддон до последней версии. Подробности: /il info")
    end
end

local function PrintInfo()
    local client, toc = ClientBuild()
    Print("клиент: сборка " .. client .. ", Interface " .. tostring(toc))
    Print("база собрана для сборки " .. (ItemLocDataBuild or "неизвестно"))
    EnsureActive()
    for _, loc in ipairs(ActiveLocales()) do
        local d = ItemLocData[loc]
        if d then
            local count = 0
            for _ in pairs(d.n) do count = count + 1 end
            Print(loc .. ": " .. (d.empty and "нет данных для этой версии игры" or (count .. " названий")))
        else
            Print(loc .. ": модуль не загружен (" .. tostring(loadReason[loc] or "нет папки ItemLoc_" .. loc) .. ")")
        end
    end
end

---------------------------------------------------------------------------
-- Загрузка настроек и команды
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ItemLocDB = ItemLocDB or { strict = false }
        db = ItemLocDB
        if type(db.langs) ~= "table" then
            -- первый запуск: английский + язык клиента игрока
            db.langs = {}
            local clientLocale = GetLocale()
            if clientLocale == "enGB" then clientLocale = "enUS" end
            if clientLocale ~= "enUS" then db.langs[clientLocale] = true end
        end
        db.langs.enUS = nil   -- английский включён всегда и отдельно не хранится
        UpdateModeText()
    elseif event == "PLAYER_LOGIN" then
        -- небольшая пауза, чтобы сообщение не потерялось среди других при входе
        if C_Timer and C_Timer.After then C_Timer.After(4, CheckClientBuild) else CheckClientBuild() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        for i = 1, ROWS_COUNT do
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
    msg = msg or ""
    local cmd = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "info" then PrintInfo() return end
    if cmd == "lang" or cmd == "config" or cmd == "языки" then OpenOptions() return end
    if msg ~= "" then
        frame:Show()
        edit:SetText(msg)
        DoSearch()
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
