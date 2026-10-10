"""Проверяет, что список языков одинаков в build_data.py, Polyglot.lua и .pkgmeta."""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import build_data

lua = open(os.path.join(ROOT, "Polyglot.lua"), encoding="utf-8").read()
start = lua.index("local LOCALES = {")
block = lua[start:lua.index("\n}\n", start)]
in_lua = re.findall(r'\{\s*"(\w+)"\s*,', block)

pkg = open(os.path.join(ROOT, ".pkgmeta"), encoding="utf-8").read()
in_pkg = re.findall(r"Polyglot/Modules/Polyglot_(\w+):\s*Polyglot_(\w+)", pkg)

in_py = list(build_data.LOCALES)
errors = []
if in_lua != in_py:
    errors.append(f"Polyglot.lua и build_data.py расходятся:\n  Lua: {in_lua}\n  Python: {in_py}")
if [a for a, _ in in_pkg] != in_py or any(a != b for a, b in in_pkg):
    errors.append(f".pkgmeta и build_data.py расходятся:\n  .pkgmeta: {[a for a, _ in in_pkg]}\n  Python: {in_py}")
if errors:
    sys.exit("ОШИБКА: списки языков не совпадают.\n" + "\n".join(errors))
print(f"Списки языков совпадают ({len(in_py)}): {', '.join(in_py)}")
