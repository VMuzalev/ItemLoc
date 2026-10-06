"""
build_data.py - собирает LocalizationData.lua для аддона ItemLoc.

Данные берутся из таблицы ItemSparse через wago.tools:
  1) клиент WoW Forever (главный источник);
  2) клиент Classic Era (запасной): часть предметов в таблицах Forever отсутствует,
     хотя в игре они есть. Названия таких предметов берутся из Classic Era.

Запуск:    python tools/build_data.py
Результат: файл LocalizationData.lua рядом с ItemLoc.toc
"""
import csv
import io
import os
import sys
import urllib.error
import urllib.request

# Сборки пробуются по очереди, берётся первая, которая скачалась.
# Актуальные номера: https://wago.tools/builds
FOREVER_BUILDS = ["1.60.1.70205", "1.60.1.70170"]      # продукт wow_classic_beta
CLASSIC_ERA_BUILDS = ["1.15.9.69722"]                  # продукт wow_classic_era

# Ключ в аддоне -> код языка в wago.tools. Можно добавить: "fr": "frFR", "es": "esES"
LOCALES = {"en": "enUS", "ru": "ruRU", "de": "deDE"}

# Защита от испорченных данных: если предметов меньше, скрипт остановится и файл не будет записан.
MIN_ITEMS = 10000

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "LocalizationData.lua")


def download(build, locale_code):
    url = f"https://wago.tools/db2/ItemSparse/csv?build={build}&locale={locale_code}"
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


def load_source(label, builds):
    """Пробует сборки по очереди. Возвращает ({язык: {id: название}}, номер сборки)"""
    for build in builds:
        try:
            data = {key: parse(download(build, code)) for key, code in LOCALES.items()}
        except urllib.error.URLError as e:
            print(f"  {label} {build}: не получилось ({e}), пробую следующую сборку")
            continue
        print(f"  {label} {build}: {len(data['en'])} предметов")
        return data, build
    sys.exit(f"Не удалось скачать данные {label}. Проверьте номера сборок на wago.tools/builds")


def merge(primary, fallback):
    """Данные primary главнее, пустые названия добираются из fallback."""
    merged = {}
    for key in LOCALES:
        d = dict(fallback[key])
        for item_id, name in primary[key].items():
            if name or item_id not in d:
                d[item_id] = name
        merged[key] = d
    return merged


def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", " ")
    return '"' + s + '"'


def main():
    forever, forever_build = load_source("Forever", FOREVER_BUILDS)
    era, _ = load_source("Classic Era", CLASSIC_ERA_BUILDS)
    names = merge(forever, era)

    only_era = len(set(era["en"]) - set(forever["en"]))
    print(f"Из Classic Era добавлено предметов, которых нет в Forever: {only_era}")

    # Проверка: если язык не переключился, русские названия совпадут с английскими
    if "ru" in names:
        same = sum(1 for i, n in names["ru"].items() if n and n == names["en"].get(i))
        if same / max(1, len(names["ru"])) > 0.8:
            sys.exit("ОШИБКА: русские названия почти совпадают с английскими, "
                     "похоже, wago.tools не переключил язык. Файл не записан.")

    keys = list(LOCALES.keys())
    ids = sorted(i for i, n in names["en"].items() if n)
    if len(ids) < MIN_ITEMS:
        sys.exit(f"ОШИБКА: найдено только {len(ids)} предметов (ожидается не меньше {MIN_ITEMS}). Файл не записан.")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"ItemLocDataBuild = {lua_str(forever_build)}\n")   # для проверки версии в аддоне
        f.write("ItemLocLocales = {" + ",".join(lua_str(k) for k in keys) + "}\n")
        f.write("ItemLocData = {\n")
        for item_id in ids:
            row = [names[k].get(item_id, "") for k in keys]
            shown = ",".join(lua_str(n) for n in row)
            low = ",".join(lua_str(n.lower()) for n in row)
            f.write(f"[{item_id}]={{{{{shown}}},{{{low}}}}},\n")
        f.write("}\n")

    print(f"Готово: {len(ids)} предметов записано в {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
