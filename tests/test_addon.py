import os
import shutil
import unittest

from helpers import Game, build_workspace, fake_download, run_build

NAMES = {
    "enUS": {1: "Thunderfury, Blessed Blade of the Windseeker", 2: "Hearthstone", 3: "Hearthstone Charm"},
    "ruRU": {1: "Громовая Ярость, благословенный клинок Искателя Ветра", 2: "Камень возвращения", 3: "Амулет камня"},
    "deDE": {1: "Donnerfury, Geschenk des Windsuchers", 2: "Ruhestein", 3: "Ärmel"},
}


class AddonTestCase(unittest.TestCase):
    def setUp(self):
        self.ctx = build_workspace(fake_download(count=300, overrides=NAMES))
        self.root = self.ctx.__enter__()
        run_build()
        self.modules = os.path.join(self.root, "Modules")

    def tearDown(self):
        self.ctx.__exit__(None, None, None)

    def game(self, **kw):
        return Game(self.modules, **kw)


class Languages(AddonTestCase):
    def test_defaults_follow_client_locale(self):
        self.assertEqual(self.game(locale="ruRU").langs(), "ruRU")
        self.assertEqual(self.game(locale="deDE").langs(), "deDE")
        self.assertEqual(self.game(locale="enUS").langs(), "")
        self.assertEqual(self.game(locale="enGB").langs(), "")

    def test_old_saved_settings_survive_migration(self):
        g = self.game(locale="enGB", saved="{ strict = true }")
        self.assertTrue(g.ev("db.strict"))
        self.assertEqual(g.langs(), "")

    def test_nothing_loads_until_window_is_opened(self):
        g = self.game()
        self.assertEqual(g.loaded(), "")
        g.slash("")
        self.assertEqual(g.loaded(), "ItemLoc_enUS,ItemLoc_ruRU")

    def test_enabling_a_language_loads_only_that_module(self):
        g = self.game(); g.slash("")
        g.toggle_language("deDE", True)
        self.assertEqual(g.loaded(), "ItemLoc_enUS,ItemLoc_ruRU,ItemLoc_deDE")
        self.assertEqual(g.langs(), "deDE,ruRU")

    def test_disabled_language_is_not_searched(self):
        g = self.game(); g.slash("")
        self.assertEqual(g.search("ruhestein")[0], 0)           # немецкий не включён
        g.toggle_language("deDE", True)
        self.assertEqual(g.search("ruhestein"), (1, ["2:1"]))
        g.toggle_language("deDE", False)
        self.assertEqual(g.search("ruhestein")[0], 0)

    def test_missing_module_is_reported_but_others_work(self):
        shutil.rmtree(os.path.join(self.modules, "ItemLoc_frFR"))
        g = self.game(); g.slash("")
        g.toggle_language("frFR", True)
        self.assertIn("не найден", g.ev("statuses.frFR._text"))
        g.type_and_search("hearthstone")
        self.assertIn("frFR", g.ev("status._text"))
        self.assertGreater(g.search("hearthstone")[0], 0)

    def test_missing_english_module_shows_reinstall_hint(self):
        shutil.rmtree(os.path.join(self.modules, "ItemLoc_enUS"))
        g = self.game(); g.slash("")
        g.type_and_search("item")
        self.assertIn("ItemLoc_enUS", g.ev("status._text"))

    def test_empty_module_is_marked_as_no_data(self):
        with build_workspace(fake_download(count=300, overrides=NAMES, fail=("koKR",))) as root:
            run_build()
            g = Game(os.path.join(root, "Modules")); g.slash("")
            g.toggle_language("koKR", True)
            self.assertIn("нет данных", g.ev("statuses.koKR._text"))


class Searching(AddonTestCase):
    def setUp(self):
        super().setUp()
        self.g = self.game()
        self.g.slash("")
        self.g.toggle_language("deDE", True)

    def test_finds_by_any_enabled_language(self):
        self.assertEqual(self.g.search("thunderfury")[1][0], "1:2")
        self.assertEqual(self.g.search("громовая ярость")[1][0], "1:2")
        self.assertEqual(self.g.search("donnerfury")[1][0], "1:2")

    def test_case_insensitive_including_cyrillic_and_umlauts(self):
        self.assertEqual(self.g.search("КАМЕНЬ ВОЗВРАЩЕНИЯ", strict=True), (1, ["2:1"]))
        self.assertEqual(self.g.search("ÄRMEL", strict=True), (1, ["3:1"]))

    def test_extra_spaces_are_ignored(self):
        self.assertEqual(self.g.search("  камень   возвращения  ", strict=True), (1, ["2:1"]))

    def test_strict_requires_full_name(self):
        self.assertEqual(self.g.search("hearthstone", strict=True), (1, ["2:1"]))
        self.assertEqual(self.g.search("камень", strict=True)[0], 0)

    def test_non_strict_ranks_exact_then_prefix(self):
        count, items = self.g.search("hearthstone")
        self.assertEqual(items[:2], ["2:1", "3:2"])

    def test_words_in_any_order(self):
        self.assertEqual(self.g.search("ветра искателя"), (1, ["1:4"]))
        self.assertEqual(self.g.search("ветра искателя", strict=True)[0], 0)


class Pagination(AddonTestCase):
    def setUp(self):
        super().setUp()
        self.g = self.game(locale="enUS")
        self.g.slash("")
        self.g.type_and_search("item")          # результатов заметно больше одной страницы

    def label(self):
        return self.g.ev("pageText._text")

    def click(self, button, shift=False):
        self.g.lua.execute(f"SHIFT = {str(shift).lower()}; {button}._scripts.OnClick(); SHIFT = false")

    def total_pages(self):
        return int(self.label().rsplit(" ", 1)[1])

    def test_next_and_previous(self):
        self.assertTrue(self.label().startswith("Стр. 1 из "))
        self.assertFalse(self.g.ev("prevBtn._enabled"))
        self.click("nextBtn")
        self.assertTrue(self.label().startswith("Стр. 2 из "))
        self.assertTrue(self.g.ev("prevBtn._enabled"))
        self.click("prevBtn")
        self.assertTrue(self.label().startswith("Стр. 1 из "))

    def test_shift_click_jumps_to_edges_and_last_page_disables_next(self):
        pages = self.total_pages()
        self.click("nextBtn", shift=True)
        self.assertEqual(self.label(), f"Стр. {pages} из {pages}")
        self.assertFalse(self.g.ev("nextBtn._enabled"))
        self.click("nextBtn")                                   # дальше последней не уходит
        self.assertEqual(self.label(), f"Стр. {pages} из {pages}")
        self.click("prevBtn", shift=True)
        self.assertTrue(self.label().startswith("Стр. 1 из "))

    def test_mouse_wheel(self):
        self.g.lua.execute("frame._scripts.OnMouseWheel(frame, -1)")
        self.assertTrue(self.label().startswith("Стр. 2 из "))
        self.g.lua.execute("frame._scripts.OnMouseWheel(frame, 1)")
        self.assertTrue(self.label().startswith("Стр. 1 из "))

    def test_new_search_returns_to_first_page(self):
        self.click("nextBtn")
        self.g.type_and_search("item 1")
        self.assertTrue(self.label().startswith("Стр. 1 из "))

    def test_rows_per_page_shrink_with_more_languages(self):
        english_only = self.g.ev("perPage")
        self.g.lua.execute("db.langs = {ruRU=true, deDE=true, esES=true, itIT=true, ptBR=true, esMX=true, "
                           "koKR=true, zhCN=true, zhTW=true, frFR=true}; DoSearch()")
        self.assertLess(self.g.ev("perPage"), english_only)
        self.assertGreaterEqual(self.g.ev("perPage"), 1)


class ClientBuildNotice(AddonTestCase):
    def test_silent_when_builds_match(self):
        g = self.game(client_build="70205", data_build="1.60.1.70205")
        g.fire("PLAYER_LOGIN")
        self.assertEqual(g.printed(), [])

    def test_notice_when_client_updated_and_only_once(self):
        g = self.game(client_build="70300", data_build="1.60.1.70205")
        g.fire("PLAYER_LOGIN")
        self.assertEqual(len(g.printed()), 1)
        self.assertIn("70300", g.printed()[0]); self.assertIn("70205", g.printed()[0])
        g.fire("PLAYER_LOGIN")
        self.assertEqual(len(g.printed()), 1)

    def test_notice_when_build_marker_missing(self):
        g = self.game(data_build=None)
        g.fire("PLAYER_LOGIN")
        self.assertIn("метки сборки", g.printed()[0])

    def test_info_command(self):
        g = self.game(); g.slash("info")
        text = "\n".join(g.printed())
        self.assertIn("Interface 16001", text); self.assertIn("enUS: 300 названий", text); self.assertIn("ruRU: 300 названий", text)


class Settings(AddonTestCase):
    def test_options_panel_registered_and_openable(self):
        g = self.game()
        self.assertTrue(g.ev("REGISTERED ~= nil"))
        g.slash("lang")
        self.assertEqual(g.ev("OPENED"), 42)


if __name__ == "__main__":
    unittest.main()
