"""
build_data.py - собирает LocalizationData.lua для аддона ItemLoc.

Данные берутся из таблицы ItemSparse клиента WoW Forever через wago.tools.
Запуск:   python build_data.py
Результат: файл ItemLoc/LocalizationData.lua в папке аддона.
"""
import csv
import io
import sys
import urllib.request

# Номер сборки Forever. Актуальный список: https://wago.tools/builds
# (ищите продукт wow_classic_beta, версии вида 1.60.1.xxxxx)
BUILD = "1.60.1.70170"

# Ключ в аддоне -> код языка в wago.tools. Добавляйте языки по желанию:
# "fr": "frFR", "es": "esES"
LOCALES = {"en": "enUS", "ru": "ruRU", "de": "deDE"}

import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ItemLoc", "LocalizationData.lua")


def download(locale_code):
    url = f"https://wago.tools/db2/ItemSparse/csv?build={BUILD}&locale={locale_code}"
    print("Скачиваю:", url)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ItemLoc builder)"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read().decode("utf-8-sig")


def parse(text):
    reader = csv.DictReader(io.StringIO(text))
    cols = reader.fieldnames or []
    if "ID" not in cols or "Display_lang" not in cols:
        sys.exit("Не нашёл колонки ID / Display_lang. Первые колонки файла: " + ", ".join(cols[:15]))
    result = {}
    for row in reader:
        if row["ID"].isdigit():
            result[int(row["ID"])] = row["Display_lang"].strip()
    return result


def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", " ")
    return '"' + s + '"'


def main():
    names = {}
    for key, code in LOCALES.items():
        names[key] = parse(download(code))
        print(f"  {key}: {len(names[key])} записей")

    # Проверка: если язык не переключился, русские названия совпадут с английскими
    if "ru" in names and "en" in names:
        same = sum(1 for i, n in names["ru"].items() if n and n == names["en"].get(i))
        total = max(1, len(names["ru"]))
        if same / total > 0.8:
            print("ВНИМАНИЕ: русские названия почти совпадают с английскими, "
                  "похоже, wago.tools не переключил язык. Напишите об этом в чат.")

    keys = list(LOCALES.keys())
    ids = sorted(i for i, n in names["en"].items() if n)

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("ItemLocLocales = {" + ",".join(lua_str(k) for k in keys) + "}\n")
        f.write("ItemLocData = {\n")
        for item_id in ids:
            row = [names[k].get(item_id, "") for k in keys]
            shown = ",".join(lua_str(n) for n in row)
            low = ",".join(lua_str(n.lower()) for n in row)
            f.write(f"[{item_id}]={{{{{shown}}},{{{low}}}}},\n")
        f.write("}\n")

    print(f"Готово: {len(ids)} предметов записано в {os.path.normpath(OUT)}")


main()
