import os
import unittest
import urllib.error

import helpers
from helpers import build_data as b, build_workspace, fake_download, lua51, read, run_build


class Merge(unittest.TestCase):
    def test_primary_wins_and_fallback_fills_gaps(self):
        primary = {loc: None for loc in b.LOCALES}
        fallback = {loc: None for loc in b.LOCALES}
        primary["ruRU"] = {1: "Новое", 2: ""}
        fallback["ruRU"] = {1: "Старое", 2: "Из запасного", 3: "Только в запасном"}
        merged = b.merge(primary, fallback)["ruRU"]
        self.assertEqual(merged, {1: "Новое", 2: "Из запасного", 3: "Только в запасном"})

    def test_locale_missing_everywhere_stays_none(self):
        none = {loc: None for loc in b.LOCALES}
        self.assertIsNone(b.merge(none, none)["koKR"])


class Discovery(unittest.TestCase):
    def test_extracts_only_forever_versions_newest_first(self):
        text = ('1.15.9.69722 {"version":"1.60.1.70205"} 1.60.1.69977 3.4.5.12345 '
                '11.2.0.61234 1.60.1.7020512 "1.60.2.70300"')
        self.assertEqual(b.extract_forever_versions(text), ["1.60.2.70300", "1.60.1.70205", "1.60.1.69977"])

    def test_blizzard_version_server_format(self):
        text = "Region!STRING:0|BuildId!DEC:4|VersionsName!String:0\nus|70205|1.60.1.70205\neu|70205|1.60.1.70205"
        self.assertEqual(b.extract_forever_versions(text), ["1.60.1.70205"])

    def test_discovery_failures_are_not_fatal(self):
        old = b._fetch_text
        b._fetch_text = lambda url, timeout=60: (_ for _ in ()).throw(OSError("нет сети"))
        try:
            self.assertEqual(b.discover_forever_builds(), [])
        finally:
            b._fetch_text = old

    def test_discovered_builds_go_first_then_static_fallback(self):
        old = b.discover_forever_builds
        b.discover_forever_builds = lambda: ["1.60.1.99999", "1.60.1.88888", "1.60.1.77777", "1.60.1.66666"]
        try:
            candidates = b.forever_build_candidates()
            self.assertEqual(candidates[:3], ["1.60.1.99999", "1.60.1.88888", "1.60.1.77777"])
            for fallback in b.FOREVER_BUILDS:
                self.assertIn(fallback, candidates)
        finally:
            b.discover_forever_builds = old


class Validate(unittest.TestCase):
    def merged(self, **overrides):
        en = {i: f"Item {i}" for i in range(1, 301)}
        data = {loc: {i: f"{loc} {i}" for i in range(1, 301)} for loc in b.LOCALES}
        data["enUS"] = en
        data.update(overrides)
        return data

    def test_ok(self):
        old = b.MIN_ITEMS; b.MIN_ITEMS = 100
        try:
            result = b.validate(self.merged())
            self.assertTrue(all(result[loc] for loc in b.LOCALES))
        finally:
            b.MIN_ITEMS = old

    def test_required_language_same_as_english_stops_build(self):
        old = b.MIN_ITEMS; b.MIN_ITEMS = 100
        try:
            same = {i: f"Item {i}" for i in range(1, 301)}
            with self.assertRaises(SystemExit):
                b.validate(self.merged(ruRU=same))
        finally:
            b.MIN_ITEMS = old

    def test_optional_language_problem_becomes_empty(self):
        old = b.MIN_ITEMS; b.MIN_ITEMS = 100
        try:
            result = b.validate(self.merged(koKR={1: "x"}, frFR=None))
            self.assertIsNone(result["koKR"])
            self.assertIsNone(result["frFR"])
            self.assertIsNotNone(result["deDE"])
        finally:
            b.MIN_ITEMS = old

    def test_too_few_english_names_stops_build(self):
        old = b.MIN_ITEMS; b.MIN_ITEMS = 100000
        try:
            with self.assertRaises(SystemExit):
                b.validate(self.merged())
        finally:
            b.MIN_ITEMS = old


class FullBuild(unittest.TestCase):
    def test_generates_all_modules_and_build_marker(self):
        with build_workspace(fake_download(), interface="16002") as root:
            run_build()
            modules = sorted(os.listdir(os.path.join(root, "Modules")))
            self.assertEqual(modules, sorted(f"ItemLoc_{loc}" for loc in b.LOCALES))
            with open(os.path.join(root, "Build.lua"), encoding="utf-8") as f:
                self.assertEqual(f.read().strip(), 'ItemLocDataBuild = "1.60.1.70205"')
            toc = read(root, "Modules", "ItemLoc_ruRU", "ItemLoc_ruRU.toc")
            self.assertIn("## Interface: 16002", toc)        # берётся из основного ItemLoc.toc
            self.assertIn("## LoadOnDemand: 1", toc)
            self.assertIn("## Dependencies: ItemLoc", toc)
            self.assertIn("## Group: ItemLoc", toc)          # группировка в списке аддонов
            self.assertIn("## IconTexture: Interface\\Icons\\INV_Misc_Book_04", toc)   # иконка в списке аддонов

    def test_data_files_load_in_lua51_across_chunks(self):
        # 9000 предметов = 3 блока по 4000: проверяем, что разбиение на блоки не теряет записи
        with build_workspace(fake_download(count=9000)) as root:
            run_build()
            lua = lua51.LuaRuntime()
            for loc in ("enUS", "ruRU"):
                lua.execute(read(root, "Modules", f"ItemLoc_{loc}", "Data.lua"))
            self.assertEqual(lua.eval('ItemLocData.ruRU.n[8999]'), "Предмет 8999")
            self.assertEqual(lua.eval('ItemLocData.ruRU.l[8999]'), "предмет 8999")
            self.assertEqual(lua.eval('(function() local c = 0 for _ in pairs(ItemLocData.enUS.n) do c = c + 1 end return c end)()'), 9000)

    def test_special_characters_are_escaped(self):
        names = {5: 'Quote " and \\ backslash', 6: "Ärmel и Ёлка"}
        with build_workspace(fake_download(overrides={"enUS": names})) as root:
            run_build()
            lua = lua51.LuaRuntime()
            lua.execute(read(root, "Modules", "ItemLoc_enUS", "Data.lua"))
            self.assertEqual(lua.eval("ItemLocData.enUS.n[5]"), 'Quote " and \\ backslash')
            self.assertEqual(lua.eval("ItemLocData.enUS.l[6]"), "ärmel и ёлка")

    def test_optional_language_missing_gives_empty_module(self):
        with build_workspace(fake_download(fail=("koKR",))) as root:
            run_build()
            data = read(root, "Modules", "ItemLoc_koKR", "Data.lua")
            self.assertIn("empty = true", data)

    def test_required_language_failure_writes_nothing(self):
        with build_workspace(fake_download(fail=("ruRU",))) as root:
            with self.assertRaises(SystemExit):
                run_build()
            self.assertFalse(os.path.exists(os.path.join(root, "Modules")))
            self.assertFalse(os.path.exists(os.path.join(root, "Build.lua")))

    def test_check_mode_prints_only_the_build(self):
        import contextlib, io
        with build_workspace(fake_download()):
            out, err = io.StringIO(), io.StringIO()
            old_argv = helpers.sys.argv
            helpers.sys.argv = ["build_data.py", "--check"]
            try:
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    b.main()
            finally:
                helpers.sys.argv = old_argv
            self.assertEqual(out.getvalue().strip(), "1.60.1.70205")


if __name__ == "__main__":
    unittest.main()
