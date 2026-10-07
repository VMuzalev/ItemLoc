"""Общие вспомогательные средства тестов: фиктивные данные wago.tools и заглушки игрового API."""
import contextlib
import csv
import io
import os
import shutil
import sys
import tempfile

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))

import build_data  # noqa: E402
from lupa import lua51  # noqa: E402


def csv_text(rows):
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(["ID", "Display_lang"])
    writer.writerows(rows)
    return buf.getvalue()


def read(*path):
    with open(os.path.join(*path), encoding="utf-8") as f:
        return f.read()


def fake_download(count=9000, overrides=None, fail=()):
    """Подменяет скачивание: названия вида 'Item 5', 'Предмет 5', 'Gegenstand 5'.
    overrides: {локаль: {id: название}}, fail: локали, которые «не скачались» (404)."""
    import urllib.error
    prefix = {"enUS": "Item", "ruRU": "Предмет", "deDE": "Gegenstand"}
    overrides = overrides or {}

    def download(build, locale, attempts=3):
        if locale in fail:
            raise urllib.error.HTTPError("u", 404, "Not Found", {}, None)
        word = prefix.get(locale, locale)
        names = {i: f"{word} {i}" for i in range(1, count + 1)}
        names.update(overrides.get(locale, {}))
        return csv_text(names.items())
    return download


@contextlib.contextmanager
def build_workspace(download=None, interface="16001"):
    """Временная копия «корня репозитория» для build_data. Возвращает путь к ней."""
    tmp = tempfile.mkdtemp(prefix="itemloc_test_")
    old = (build_data.ROOT, build_data.MODULES_DIR, build_data.download, build_data.MIN_ITEMS,
           build_data.forever_build_candidates)
    try:
        build_data.ROOT = tmp
        build_data.MODULES_DIR = os.path.join(tmp, "Modules")
        build_data.MIN_ITEMS = 100
        build_data.forever_build_candidates = lambda: ["1.60.1.70205"]
        if download:
            build_data.download = download
        with open(os.path.join(tmp, "ItemLoc.toc"), "w", encoding="utf-8") as f:
            f.write(f"## Interface: {interface}\n## Title: ItemLoc\nBuild.lua\nItemLoc.lua\n")
        yield tmp
    finally:
        (build_data.ROOT, build_data.MODULES_DIR, build_data.download, build_data.MIN_ITEMS,
         build_data.forever_build_candidates) = old
        shutil.rmtree(tmp, ignore_errors=True)


def run_build(quiet=True):
    out = io.StringIO()
    with contextlib.redirect_stdout(out if quiet else sys.stdout):
        build_data.main()
    return out.getvalue()


# ---------------------------------------------------------------- Lua и заглушки WoW

STUBS = r'''
local function stub()
  local o = {_scripts = {}, _shown = false}
  setmetatable(o, {__index = function(t, k)
    if k == "id" or k == "failed" or k == "link" or k:sub(1, 1) == "_" then return nil end
    if k == "GetText" then return function(self) return self._text or "" end end
    if k == "SetText" then return function(self, v) self._text = v end end
    if k == "SetAlpha" then return function(self, v) self._alpha = v end end
    if k == "SetDesaturated" then return function(self, v) self._desat = v end end
    if k == "SetChecked" then return function(self, v) self._checked = v end end
    if k == "GetChecked" then return function(self) return self._checked end end
    if k == "SetScript" then return function(self, n, f) self._scripts[n] = f end end
    if k == "Enable" then return function(self) self._enabled = true end end
    if k == "Disable" then return function(self) self._enabled = false end end
    if k == "IsShown" then return function(self) return self._shown end end
    if k == "Show" then return function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return stub() end end
    return function(self, ...) return self end
  end})
  return o
end
UIParent = stub(); GameTooltip = stub(); BackdropTemplateMixin = {}; UISpecialFrames = {}
tinsert = table.insert; SlashCmdList = {}
FRAMES = {}
CreateFrame = function() local f = stub(); FRAMES[#FRAMES+1] = f; return f end
ITEM_QUALITY_COLORS = {}
PRINTED = {}
print = function(...) PRINTED[#PRINTED+1] = table.concat({...}, " ") end
C_Timer = { After = function(_, f) f() end }
IsShiftKeyDown = function() return SHIFT end
SHIFT = false
LOADED = {}
C_AddOns = { LoadAddOn = function(name)
    local src = read_module(name)
    if not src then return nil, "MISSING" end
    LOADED[#LOADED + 1] = name
    assert(loadstring(src, name))()
    return true
end }
Minimap = stub()
Minimap.GetWidth = function() return 140 end
Minimap.GetCenter = function() return 100, 100 end
Minimap.GetEffectiveScale = function() return 1 end
GetCursorPosition = function() return 100, 200 end
AddonCompartmentFrame = { RegisterAddon = function(self, info) COMPARTMENT = info end }
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return 42 end } end,
    RegisterAddOnCategory = function(c) REGISTERED = c end,
    OpenToCategory = function(id) OPENED = id end,
}
'''

# Локальные переменные аддона, которые тестам нужно видеть: делаем их глобальными
EXPOSE = [
    ("local rows = {}", "rows = {}"), ("local frame = CreateFrame", "frame = CreateFrame"),
    ("local edit = CreateFrame", "edit = CreateFrame"), ("local status = frame", "status = frame"),
    ("local pageText = frame", "pageText = frame"), ("local checks, statuses = {}, {}", "checks, statuses = {}, {}"),
    ("local rowH, perPage", "rowH, perPage"), ("local function Search", "function Search"),
    ("local function normalize", "function normalize"), ("local DoSearch ", "DoSearch = nil -- "),
    ("local db = ", "db = "), ("local panel = CreateFrame", "panel = CreateFrame"),
    ("local prevBtn", "prevBtn"), ("local nextBtn", "nextBtn"), ("local minimapBtn\n", "minimapBtn = nil\n"),
    ("local favBtn", "favBtn"), ("local viewFav", "viewFav"),
]


class Game:
    """Аддон ItemLoc, загруженный в настоящий Lua 5.1 с заглушками игрового API."""

    def __init__(self, modules_dir, locale="ruRU", saved=None, client_build="70205", data_build="1.60.1.70205"):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        L = self.lua

        def read_module(name):
            path = os.path.join(modules_dir, name, "Data.lua")
            if not os.path.exists(path):
                return None
            with open(path, encoding="utf-8") as f:
                return f.read()

        g = L.globals()
        g.read_module = read_module
        g.CLIENT_LOCALE = locale
        L.execute(STUBS)
        L.execute("GetLocale = function() return CLIENT_LOCALE end")
        L.execute(f'GetBuildInfo = function() return "1.60.1", "{client_build}", "Oct 1 2026", 16001 end')
        if data_build:
            L.execute(f'ItemLocDataBuild = "{data_build}"')
        with open(os.path.join(REPO, "ItemLoc.lua"), encoding="utf-8") as f:
            src = f.read()
        for old, new in EXPOSE:
            assert old in src, f"в ItemLoc.lua не найдено: {old}"
            src = src.replace(old, new)
        chunk = L.eval("function(s) return loadstring(s, 'ItemLoc') end")(src)
        assert not isinstance(chunk, tuple), chunk
        chunk("ItemLoc")
        if saved is not None:
            L.execute(f"ItemLocDB = {saved}")
        self.fire("ADDON_LOADED", '"ItemLoc"')

    def fire(self, event, arg='nil'):
        self.lua.execute(f'for _, f in ipairs(FRAMES) do if f._scripts.OnEvent then '
                         f'f._scripts.OnEvent(f, "{event}", {arg}) end end')

    def slash(self, text=""):
        self.lua.execute(f"SlashCmdList['ITEMLOC']({text!r})".replace("'", '"'))

    def search(self, query, strict=False, limit=5):
        """Возвращает (число результатов, [id:оценка ...])."""
        r = self.lua.eval(
            f'(function() local r = Search(normalize("{query}"), {str(strict).lower()}); local o = {{}} '
            f'for i = 1, math.min(#r, {limit}) do o[#o + 1] = r[i].id .. ":" .. r[i].score end '
            f'return #r .. "|" .. table.concat(o, ",") end)()')
        count, _, items = r.partition("|")
        return int(count), [x for x in items.split(",") if x]

    def type_and_search(self, text):
        self.lua.execute(f'edit._text = "{text}"; DoSearch()')

    def langs(self):
        return self.lua.eval("(function() local o = {} for k in pairs(db.langs) do o[#o+1] = k end "
                             "table.sort(o) return table.concat(o, ',') end)()")

    def loaded(self):
        return self.lua.eval('table.concat(LOADED, ",")')

    def printed(self):
        return [v.replace("|cff33ff99ItemLoc:|r ", "") for v in self.lua.eval("PRINTED").values()]

    def toggle_language(self, loc, on):
        self.lua.execute(f"checks.{loc}._checked = {str(on).lower()}; checks.{loc}._scripts.OnClick(checks.{loc})")

    def ev(self, expr):
        return self.lua.eval(expr)
