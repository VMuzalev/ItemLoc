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

-- Настройки (при входе в игру заменятся на сохранённые)
local db = { strict = false, langs = {}, favorites = {} }
local loadReason = {}   -- локаль -> почему модуль не загрузился

---------------------------------------------------------------------------
-- Тексты интерфейса: русский и английский (по языку клиента, остальные клиенты видят английский)
---------------------------------------------------------------------------
local STRINGS = {
    enUS = {
        title = "ItemLoc: item search",
        find = "Search",
        mode_strict = "Mode: strict", mode_loose = "Mode: loose",
        mode_tip = "Search mode",
        mode_tip_strict = "Strict: the name must match completely (in any enabled language).",
        mode_tip_loose = "Loose: part of a name, or all words in any order.",
        languages = "Languages...",
        favorites = "Favorites (%d)", fav_back = "Back to search",
        fav_tip = "Show only the items you marked with a star.",
        fav_add = "Add to favorites", fav_remove = "Remove from favorites",
        fav_empty = "No favorites yet. Click the star next to an item in the search results.",
        found = "Found: %d", nothing = "Nothing found", enter_query = "Enter an item name",
        missing_langs = "No data: %s",
        no_english = "Module ItemLoc_enUS not found. Reinstall the addon: all ItemLoc* folders are required.",
        page = "Page %d of %d",
        pager_tip1 = "Shift+click: first / last page", pager_tip2 = "You can also scroll with the mouse wheel",
        link_hint = "Shift+click: insert link into chat",
        loading = "loading item data...", unknown_item = "unknown to the game client (no data)",
        req_level = "req. level %d",
        opt_title = "ItemLoc: search languages",
        opt_help = "English is always used. Tick additional languages: data is loaded only for the selected "
            .. "languages, the first time the search window is opened. If you untick a language it is no "
            .. "longer searched, and its memory is freed after /reload.",
        st_loaded = "loaded", st_loaded_until = "loaded until /reload", st_empty = "no data for this game version",
        st_missing = "not found: folder ItemLoc_%s",
        opt_minimap = "Show the minimap button",
        mm_tip_title = "ItemLoc", mm_left = "Left-click: open / close", mm_right = "Right-click: language settings",
        mm_drag = "Drag: move the button",
        binding = "Open / close the ItemLoc window",
        notice_updated = "the game client was updated (build %s), but the name database was built for build %s. "
            .. "If some items are not found, update the addon (CurseForge or GitHub): a new database is published "
            .. "automatically. Details: /il info",
        notice_nomarker = "the addon has no database build marker. Update the addon to the latest version. Details: /il info",
        info_client = "client: build %s, Interface %s", info_db = "database built for build %s", unknown = "unknown",
        info_names = "%s: %d names", info_nodata = "%s: no data for this game version",
        info_notloaded = "%s: module not loaded (%s)", info_nofolder = "no folder ItemLoc_%s",
        no_options = "settings are not available in this client version",
        minimap_on = "minimap button shown", minimap_off = "minimap button hidden",
        welcome = "installed. Open the window with /il or the minimap button. Languages: /il lang. Help: /il help",
        help_title = "commands:",
        help_1 = "/il - open or close the window", help_2 = "/il <name> - search right away",
        help_3 = "/il lang - choose search languages", help_4 = "/il minimap - show or hide the minimap button",
        help_5 = "/il info - client build, database build and language status",
        help_6 = "In the window: Enter = search, star = favorite, Shift+click = link in chat, mouse wheel = pages.",
    },
    ruRU = {
        title = "ItemLoc: поиск предметов",
        find = "Найти",
        mode_strict = "Режим: строгий", mode_loose = "Режим: нестрогий",
        mode_tip = "Режим поиска",
        mode_tip_strict = "Строгий: название должно совпасть полностью (на любом включённом языке).",
        mode_tip_loose = "Нестрогий: часть названия или слова в любом порядке.",
        languages = "Языки...",
        favorites = "Избранное (%d)", fav_back = "Назад к поиску",
        fav_tip = "Показать только предметы, отмеченные звёздочкой.",
        fav_add = "В избранное", fav_remove = "Убрать из избранного",
        fav_empty = "Избранное пусто. Нажмите на звёздочку у предмета в результатах поиска.",
        found = "Найдено: %d", nothing = "Ничего не найдено", enter_query = "Введите название предмета",
        missing_langs = "Нет данных: %s",
        no_english = "Не найден модуль ItemLoc_enUS. Переустановите аддон: нужны все папки ItemLoc*.",
        page = "Стр. %d из %d",
        pager_tip1 = "Shift+клик: в начало / в конец", pager_tip2 = "Также можно листать колесом мыши",
        link_hint = "Shift+клик: вставить ссылку в чат",
        loading = "загрузка данных из игры...", unknown_item = "игра не знает этот предмет (нет данных в клиенте)",
        req_level = "треб. ур. %d",
        opt_title = "ItemLoc: языки поиска",
        opt_help = "Английский используется всегда. Отметьте дополнительные языки: данные загружаются только "
            .. "для выбранных языков, при первом открытии окна поиска. Если снять галочку, язык перестанет "
            .. "участвовать в поиске, а память освободится после /reload.",
        st_loaded = "загружен", st_loaded_until = "загружен до /reload", st_empty = "нет данных для этой версии игры",
        st_missing = "не найден: папка ItemLoc_%s",
        opt_minimap = "Показывать кнопку у миникарты",
        mm_tip_title = "ItemLoc", mm_left = "Левый клик: открыть / закрыть", mm_right = "Правый клик: языки поиска",
        mm_drag = "Перетаскивание: переместить кнопку",
        binding = "Открыть / закрыть окно ItemLoc",
        notice_updated = "клиент игры обновился (сборка %s), а база названий собрана для сборки %s. "
            .. "Если какие-то предметы не находятся, обновите аддон (CurseForge или GitHub): "
            .. "новая база выходит автоматически. Подробности: /il info",
        notice_nomarker = "в аддоне нет метки сборки базы. Обновите аддон до последней версии. Подробности: /il info",
        info_client = "клиент: сборка %s, Interface %s", info_db = "база собрана для сборки %s", unknown = "неизвестно",
        info_names = "%s: %d названий", info_nodata = "%s: нет данных для этой версии игры",
        info_notloaded = "%s: модуль не загружен (%s)", info_nofolder = "нет папки ItemLoc_%s",
        no_options = "настройки недоступны в этой версии клиента",
        minimap_on = "кнопка у миникарты показана", minimap_off = "кнопка у миникарты скрыта",
        welcome = "установлен. Откройте окно командой /il или кнопкой у миникарты. Языки: /il lang. Справка: /il help",
        help_title = "команды:",
        help_1 = "/il - открыть или закрыть окно", help_2 = "/il <название> - сразу выполнить поиск",
        help_3 = "/il lang - выбрать языки поиска", help_4 = "/il minimap - показать или скрыть кнопку у миникарты",
        help_5 = "/il info - сборка клиента, сборка базы и состояние языков",
        help_6 = "В окне: Enter = поиск, звёздочка = избранное, Shift+клик = ссылка в чат, колесо мыши = страницы.",
    },
}
local CURRENT = STRINGS[GetLocale()] or STRINGS.enUS

local function T(key, ...)
    local s = CURRENT[key] or STRINGS.enUS[key] or key
    if select("#", ...) > 0 then return s:format(...) end
    return s
end

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
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

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
local BODY_H = 360        -- высота области результатов
local ROWS_COUNT = 7      -- сколько строк создано; сколько показано, зависит от числа языков
local FAVORITE_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"   -- жёлтая звезда

local frame = CreateFrame("Frame", "ItemLocFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(FRAME_W, 110 + BODY_H + 80)
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
title:SetText(T("title"))

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
searchBtn:SetText(T("find"))

local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
modeBtn:SetSize(150, 24)
modeBtn:SetPoint("TOPLEFT", 24, -78)

local langBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
langBtn:SetSize(95, 24)
langBtn:SetPoint("LEFT", modeBtn, "RIGHT", 6, 0)
langBtn:SetText(T("languages"))

local favBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
favBtn:SetSize(150, 24)
favBtn:SetPoint("LEFT", langBtn, "RIGHT", 6, 0)

-- Строка состояния внизу, над переключателем страниц
local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOM", 0, 50)
status:SetWidth(FRAME_W - 48)
status:SetJustifyH("CENTER")

local function UpdateModeText()
    modeBtn:SetText(db.strict and T("mode_strict") or T("mode_loose"))
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
    row.text:SetWidth(FRAME_W - 48 - 64 - 24)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    -- Звёздочка избранного
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(18, 18)
    row.star:SetPoint("TOPRIGHT", -6, -6)
    row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
    row.star.tex:SetAllPoints()
    row.star.tex:SetTexture(FAVORITE_ICON)

    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
        if self.link then
            GameTooltip:AddLine(T("link_hint"), 0.6, 0.6, 0.6)
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
local rowH, perPage = 56, 5
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
-- Избранное
---------------------------------------------------------------------------
local viewFav = false   -- показан список избранного вместо результатов поиска
local DoSearch          -- объявлена ниже

local function FavoriteCount()
    local n = 0
    for _ in pairs(db.favorites) do n = n + 1 end
    return n
end

local function UpdateFavBtn()
    favBtn:SetText(viewFav and T("fav_back") or T("favorites", FavoriteCount()))
end

local function UpdateStar(row)
    local on = row.id and db.favorites[row.id]
    row.star.tex:SetDesaturated(not on)
    row.star.tex:SetAlpha(on and 1 or 0.4)
end

-- Список избранного: все отмеченные предметы или только подходящие под запрос
local function FavoriteList(query)
    local out = {}
    if query ~= "" then
        for _, r in ipairs(Search(query, db.strict)) do
            if db.favorites[r.id] then out[#out + 1] = r end
        end
        return out
    end
    for id in pairs(db.favorites) do out[#out + 1] = { id = id, score = 0 } end
    local en = ItemLocData.enUS
    table.sort(out, function(a, b)
        local na = en and en.l[a.id] or ""
        local nb = en and en.l[b.id] or ""
        if na ~= nb then return na < nb end
        return a.id < b.id
    end)
    return out
end

---------------------------------------------------------------------------
-- Постраничный просмотр
---------------------------------------------------------------------------
local currentResults, page = {}, 1
local statusExtra = ""             -- дописывается к строке состояния (например, нет данных для языка)
local emptyText = T("nothing")     -- что писать, когда результатов нет

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
    UpdateStar(row)

    local title = g.name and (QualityHex(g.quality) .. g.name .. "|r") or (names[1] and names[1][2]) or ""
    local lines = { title .. "  |cff888888ID " .. id .. "|r" }

    if g.name then
        local meta = {}
        if g.type and g.type ~= "" then meta[#meta + 1] = g.type end
        if g.subtype and g.subtype ~= "" and g.subtype ~= g.type then meta[#meta + 1] = g.subtype end
        local slot = g.equipLoc and g.equipLoc ~= "" and _G[g.equipLoc]
        if slot then meta[#meta + 1] = slot end
        if g.ilvl and g.ilvl > 0 then meta[#meta + 1] = "iLvl " .. g.ilvl end
        if g.minLevel and g.minLevel > 0 then meta[#meta + 1] = T("req_level", g.minLevel) end
        lines[2] = "|cffbbbbbb" .. table.concat(meta, ", ") .. "|r"
    elseif row.failed then
        lines[2] = "|cffff8080" .. T("unknown_item") .. "|r"
    else
        lines[2] = "|cff888888" .. T("loading") .. "|r"
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
        status:SetText(emptyText .. statusExtra)
    else
        pageText:SetText(T("page", page, pages))
        status:SetText(T("found", total) .. statusExtra)
    end
    if page > 1 then prevBtn:Enable() else prevBtn:Disable() end
    if page < pages then nextBtn:Enable() else nextBtn:Disable() end
    UpdateFavBtn()
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
        GameTooltip:AddLine(T("pager_tip1"), 1, 1, 1)
        GameTooltip:AddLine(T("pager_tip2"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(_, delta) GoToPage(-delta) end)

---------------------------------------------------------------------------
-- Поиск из окна
---------------------------------------------------------------------------
DoSearch = function()
    local missing = EnsureActive()
    statusExtra = ""
    emptyText = T("nothing")
    if not ItemLocData.enUS then
        ShowResults({})
        status:SetText("|cffff8080" .. T("no_english") .. "|r")
        return
    end
    if #missing > 0 then
        statusExtra = "  |cffff8080" .. T("missing_langs", table.concat(missing, ", ")) .. "|r"
    end

    local q = normalize(edit:GetText())
    if viewFav then
        if FavoriteCount() == 0 then emptyText = T("fav_empty") end
        ShowResults(FavoriteList(q))
        return
    end
    if q == "" then
        emptyText = T("enter_query")
        ShowResults({})
        return
    end
    ShowResults(Search(q, db.strict))
end

local function SetFavorite(id, on)
    db.favorites[id] = on and true or nil
    if viewFav and not on then
        local keep = page
        DoSearch()           -- убрали предмет из списка избранного: обновить список, оставшись на странице
        page = keep
        ShowPage()
    else
        UpdateFavBtn()
        for i = 1, ROWS_COUNT do
            if rows[i].id == id then UpdateStar(rows[i]) end
        end
    end
end

for _, row in ipairs(rows) do
    row.star:SetScript("OnClick", function()
        if row.id then SetFavorite(row.id, not db.favorites[row.id]) end
    end)
    row.star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.id and db.favorites[row.id] and T("fav_remove") or T("fav_add"), 1, 1, 1)
        GameTooltip:Show()
    end)
    row.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    GameTooltip:AddLine(T("mode_tip"), 1, 1, 1)
    GameTooltip:AddLine(T("mode_tip_strict"), nil, nil, nil, true)
    GameTooltip:AddLine(T("mode_tip_loose"), nil, nil, nil, true)
    GameTooltip:Show()
end)
modeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
favBtn:SetScript("OnClick", function()
    viewFav = not viewFav
    DoSearch()
end)
favBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(T("fav_tip"), 1, 1, 1, true)
    GameTooltip:Show()
end)
favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- При открытии окна сразу подгружаем данные включённых языков (один раз за сессию)
frame:SetScript("OnShow", function()
    edit:SetFocus()
    EnsureActive()
    UpdateFavBtn()
end)

local function ToggleWindow()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Настройки: выбор языков и кнопка у миникарты
---------------------------------------------------------------------------
local OpenOptions = function() Print(T("no_options")) end
local ApplyMinimapVisibility   -- объявлена ниже

local panel = CreateFrame("Frame", "ItemLocOptionsPanel")
panel.name = "ItemLoc"

local pTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
pTitle:SetPoint("TOPLEFT", 16, -16)
pTitle:SetText(T("opt_title"))

local pHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
pHelp:SetPoint("TOPLEFT", pTitle, "BOTTOMLEFT", 0, -8)
pHelp:SetWidth(540)
pHelp:SetJustifyH("LEFT")
pHelp:SetText(T("opt_help"))

local checks, statuses = {}, {}
local minimapCheck

local function RefreshPanel()
    for _, info in ipairs(LOCALES) do
        local loc = info[1]
        local enabled = (loc == "enUS") or db.langs[loc] == true
        checks[loc]:SetChecked(enabled)
        local d = ItemLocData[loc]
        local text = ""
        if d and d.empty then
            text = "|cff888888" .. T("st_empty") .. "|r"
        elseif d then
            text = enabled and ("|cff00ff00" .. T("st_loaded") .. "|r") or ("|cff888888" .. T("st_loaded_until") .. "|r")
        elseif enabled then
            text = "|cffff8080" .. T("st_missing", loc) .. (loadReason[loc] and (" (" .. tostring(loadReason[loc]) .. ")") or "") .. "|r"
        end
        statuses[loc]:SetText(text)
    end
    if minimapCheck then minimapCheck:SetChecked(not db.hideMinimap) end
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

minimapCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
minimapCheck:SetPoint("TOPLEFT", pHelp, "BOTTOMLEFT", 0, -10 - #LOCALES * 28 - 10)
local minimapLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 4, 0)
minimapLabel:SetText(T("opt_minimap"))
minimapCheck:SetScript("OnClick", function(self)
    db.hideMinimap = (not self:GetChecked()) or nil
    ApplyMinimapVisibility()
end)
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
-- Кнопка у миникарты, пункт в меню аддонов, привязка клавиши
---------------------------------------------------------------------------
local minimapBtn
local function UpdateMinimapPosition()
    if not minimapBtn then return end
    local angle = math.rad(db.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 10
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function MinimapDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
    UpdateMinimapPosition()
end

if Minimap then
    minimapBtn = CreateFrame("Button", "ItemLocMinimapButton", Minimap)
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:RegisterForDrag("LeftButton")
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapBtn.icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    minimapBtn.icon:SetSize(20, 20)
    minimapBtn.icon:SetPoint("TOPLEFT", 7, -6)
    minimapBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_04")
    minimapBtn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    minimapBtn.border = minimapBtn:CreateTexture(nil, "OVERLAY")
    minimapBtn.border:SetSize(53, 53)
    minimapBtn.border:SetPoint("TOPLEFT")
    minimapBtn.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then OpenOptions() else ToggleWindow() end
    end)
    minimapBtn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", MinimapDragUpdate) end)
    minimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(T("mm_tip_title"), 1, 1, 1)
        GameTooltip:AddLine(T("mm_left"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(T("mm_right"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(T("mm_drag"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ApplyMinimapVisibility = function()
    if not minimapBtn then return end
    UpdateMinimapPosition()
    if db.hideMinimap then minimapBtn:Hide() else minimapBtn:Show() end
end

-- Пункт в меню аддонов у миникарты (если клиент это поддерживает)
if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
        text = "ItemLoc",
        icon = "Interface\\Icons\\INV_Misc_Book_04",
        notCheckable = true,
        func = function() ToggleWindow() end,
    })
end

-- Назначение клавиши: Настройки -> Управление -> Аддоны -> ItemLoc (см. Bindings.xml)
BINDING_HEADER_ITEMLOC = "ItemLoc"
BINDING_NAME_ITEMLOC_TOGGLE = T("binding")
function ItemLoc_Toggle() ToggleWindow() end

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
        Print(T("notice_updated", client, data))
    else
        Print(T("notice_nomarker"))
    end
end

local function PrintInfo()
    local client, toc = ClientBuild()
    Print(T("info_client", client, tostring(toc)))
    Print(T("info_db", ItemLocDataBuild or T("unknown")))
    EnsureActive()
    for _, loc in ipairs(ActiveLocales()) do
        local d = ItemLocData[loc]
        if d then
            local count = 0
            for _ in pairs(d.n) do count = count + 1 end
            Print(d.empty and T("info_nodata", loc) or T("info_names", loc, count))
        else
            Print(T("info_notloaded", loc, tostring(loadReason[loc] or T("info_nofolder", loc))))
        end
    end
end

local function PrintHelp()
    Print(T("help_title"))
    for i = 1, 6 do print("  " .. T("help_" .. i)) end
end

-- Приветствие один раз после установки
local function ShowWelcome()
    if db.seenWelcome then return end
    db.seenWelcome = true
    Print(T("welcome"))
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
        if type(db.favorites) ~= "table" then db.favorites = {} end
        UpdateModeText()
        UpdateFavBtn()
        ApplyMinimapVisibility()
    elseif event == "PLAYER_LOGIN" then
        local function onLogin() ShowWelcome(); CheckClientBuild() end
        -- небольшая пауза, чтобы сообщения не потерялись среди других при входе
        if C_Timer and C_Timer.After then C_Timer.After(4, onLogin) else onLogin() end
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
UpdateFavBtn()
ApplyMinimapVisibility()

SLASH_ITEMLOC1 = "/il"
SLASH_ITEMLOC2 = "/itemloc"
SlashCmdList["ITEMLOC"] = function(msg)
    msg = msg or ""
    local cmd = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "info" then PrintInfo() return end
    if cmd == "help" or cmd == "?" or cmd == "справка" then PrintHelp() return end
    if cmd == "lang" or cmd == "config" or cmd == "языки" then OpenOptions() return end
    if cmd == "minimap" then
        db.hideMinimap = (not db.hideMinimap) or nil
        ApplyMinimapVisibility()
        Print(db.hideMinimap and T("minimap_off") or T("minimap_on"))
        return
    end
    if msg ~= "" then
        frame:Show()
        edit:SetText(msg)
        DoSearch()
    else
        ToggleWindow()
    end
end
