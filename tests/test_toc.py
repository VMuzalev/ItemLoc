"""Проверка основного Polyglot.toc: категория, группа, иконка, файлы."""
import os
import re
import unittest

from helpers import REPO


class MainToc(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(REPO, "Polyglot.toc"), encoding="utf-8") as f:
            self.text = f.read()
        self.fields = dict(re.findall(r"^## ([\w-]+):\s*(.*)$", self.text, re.M))
        self.files = [l.strip() for l in self.text.splitlines() if l.strip() and not l.startswith("#")]

    def test_name_and_category(self):
        self.assertEqual(self.fields["Title"], "Polyglot")
        self.assertEqual(self.fields["Category"], "Localization")
        self.assertEqual(self.fields["Category-ruRU"], "Локализация")
        self.assertIn("Notes-ruRU", self.fields)

    def test_group_icon_saved_variables(self):
        self.assertEqual(self.fields["Group"], "Polyglot")
        self.assertIn("IconTexture", self.fields)
        self.assertEqual(self.fields["SavedVariables"], "PolyglotDB")

    def test_project_id_and_interface(self):
        self.assertTrue(self.fields["X-Curse-Project-ID"].isdigit())
        self.assertRegex(self.fields["Interface"], r"^\d{5,6}$")

    def test_files_listed_and_exist(self):
        self.assertEqual(self.files, ["Build.lua", "Polyglot.lua"])
        self.assertTrue(os.path.exists(os.path.join(REPO, "Polyglot.lua")))


if __name__ == "__main__":
    unittest.main()
