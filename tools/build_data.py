"""
build_data.py - собирает данные для аддона ItemLoc.

Данные берутся из таблицы ItemSparse через wago.tools:
  1) клиент WoW Forever (главный источник);
  2) клиент Classic Era (запасной): часть предметов в таблицах Forever отсутствует,
     хотя в игре они есть. Названия таких предметов берутся из Classic Era.

Запуск:    python tools/build_data.py
           python tools/build_data.py --check   (только определить новейшую сборку, ничего не писать)
Результат:
  Build.lua                           метка сборки (читается основным аддоном)
  Modules/ItemLoc_<локаль>/           по одному модулю на язык (загружаются по требованию)

Если репозиторий лежит прямо в Interface\\AddOns\\ItemLoc, модули дополнительно копируются
в Interface\\AddOns\\ItemLoc_<локаль>, чтобы игра их увидела (как в готовом архиве).
"""
import contextlib
import csv
import io
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request

# Сборки пробуются по очереди, берётся первая, которая скачалась.
# Актуальные номера: https://wago.tools/builds
FOREVER_BUILDS = ["1.60.1.70205", "1.60.1.70170"]      # продукт wow_classic_beta
CLASSIC_ERA_BUILDS = ["1.15.9.69722"]                  # продукт wow_classic_era

# Новые сборки Forever ищутся автоматически (см. discover_forever_builds), а список выше служит
# запасным вариантом. Если после запуска игры номер версии изменится (например, 1.61.x), добавьте префикс.
FOREVER_VERSION_PREFIXES = ("1.60.",)
# Где искать номера сборок: страница wago.tools и сервер версий Blizzard (продукт беты Forever).
DISCOVERY_URLS = (
    "https://wago.tools/builds",
    "https://us.version.battle.net/v2/products/wow_classic_beta/versions",
)

# Локаль WoW (она же код языка в wago.tools) -> подпись для списка аддонов.
# Список должен совпадать с move-folders в .pkgmeta и с LOCALES в ItemLoc.lua.
LOCALES = {
    "enUS": "English",
    "ruRU": "Русский",
    "deDE": "Deutsch",
    "frFR": "Français",
    "esES": "Español (España)",
    "esMX": "Español (México)",
    "itIT": "Italiano",
    "ptBR": "Português (Brasil)",
    "koKR": "Korean",
    "zhCN": "Chinese (Simplified)",
    "zhTW": "Chinese (Traditional)",
}

# Без этих языков релиз не собирается. Остальные при проблемах превращаются в пустой модуль.
REQUIRED = ("enUS", "ruRU")

# Защита от испорченных данных: если английских названий меньше, скрипт остановится.
MIN_ITEMS = 10000

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MODULES_DIR = os.path.join(ROOT, "Modules")
CHUNK = 4000   # записей в одном блоке (у Lua есть лимит на число констант в функции)


# ---------------------------------------------------------------- поиск сборок

def _fetch_text(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ItemLoc builder)"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", errors="replace")


def extract_forever_versions(text):
    """Достаёт из произвольного текста номера сборок Forever вида 1.60.1.70205, самые новые первыми."""
    prefixes = "|".join(re.escape(p) for p in FOREVER_VERSION_PREFIXES)
    found = set(re.findall(rf"(?<![\d.])(?:{prefixes})\d+\.\d{{5,6}}(?![\d.])", text))
    return sorted(found, key=lambda v: tuple(int(x) for x in v.split(".")), reverse=True)


def discover_forever_builds():
    """Ищет номера сборок Forever на wago.tools и сервере Blizzard. Любые сбои не критичны: вернётся []."""
    found = set()
    for url in DISCOVERY_URLS:
        try:
            versions = extract_forever_versions(_fetch_text(url))
        except Exception as e:  # сеть, формат страницы и т.д.: это только подсказка
            print(f"  Поиск сборок: {url} недоступен ({e})")
            continue
        print(f"  Поиск сборок: {url}: найдено {len(versions)}")
        found.update(versions)
    return sorted(found, key=lambda v: tuple(int(x) for x in v.split(".")), reverse=True)


def forever_build_candidates():
    """Сначала найденные автоматически (новые первыми), затем запасной список."""
    discovered = discover_forever_builds()[:3]
    return discovered + [b for b in FOREVER_BUILDS if b not in discovered]


# ---------------------------------------------------------------- загрузка

def download(build, locale, attempts=3):
    url = f"https://wago.tools/db2/ItemSparse/csv?build={build}&locale={locale}"
    print("Скачиваю:", url)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ItemLoc builder)"})
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read().decode("utf-8-sig")
        except (urllib.error.URLError, TimeoutError) as e:
            not_found = isinstance(e, urllib.error.HTTPError) and e.code == 404
            if not_found or attempt == attempts:
                raise
            print(f"  попытка {attempt} не удалась ({e}), повторяю")
            time.sleep(3 * attempt)


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
    """Пробует сборки по очереди. Возвращает ({локаль: {id: название} или None}, номер сборки)."""
    for build in builds:
        try:
            data = {"enUS": parse(download(build, "enUS"))}
        except urllib.error.URLError as e:
            print(f"  {label} {build}: не получилось ({e}), пробую следующую сборку")
            continue
        for loc in LOCALES:
            if loc == "enUS":
                continue
            try:
                data[loc] = parse(download(build, loc))
            except urllib.error.URLError as e:
                if loc in REQUIRED:
                    sys.exit(f"ОШИБКА: {label} {build}: язык {loc} не скачался ({e}).")
                print(f"  ПРЕДУПРЕЖДЕНИЕ: {label} {build}: язык {loc} не скачался ({e})")
                data[loc] = None
        print(f"  {label} {build}: {len(data['enUS'])} предметов")
        return data, build
    sys.exit(f"Не удалось скачать данные {label}. Проверьте номера сборок на wago.tools/builds")


def merge(primary, fallback):
    """Данные primary главнее, пустые названия добираются из fallback."""
    merged = {}
    for loc in LOCALES:
        p, f = primary.get(loc), fallback.get(loc)
        if p is None and f is None:
            merged[loc] = None
            continue
        d = dict(f or {})
        for item_id, name in (p or {}).items():
            if name or item_id not in d:
                d[item_id] = name
        merged[loc] = d
    return merged


def validate(merged):
    """Проверяет данные. Возвращает {локаль: {id: название} или None (модуль будет пустым)}."""
    en = merged["enUS"]
    en_count = sum(1 for n in en.values() if n)
    if en_count < MIN_ITEMS:
        sys.exit(f"ОШИБКА: английских названий {en_count}, ожидается не меньше {MIN_ITEMS}. Файлы не записаны.")

    result = {"enUS": en}
    for loc in LOCALES:
        if loc == "enUS":
            continue
        names = merged.get(loc)
        problem = None
        if not names:
            problem = "нет данных"
        else:
            filled = [(i, n) for i, n in names.items() if n]
            if len(filled) < 0.5 * en_count:
                problem = f"слишком мало названий ({len(filled)})"
            else:
                same = sum(1 for i, n in filled if n == en.get(i))
                if same / len(filled) > 0.8:
                    problem = "названия совпадают с английскими (язык не переключился)"
        if problem:
            if loc in REQUIRED:
                sys.exit(f"ОШИБКА: {loc}: {problem}. Файлы не записаны.")
            print(f"ПРЕДУПРЕЖДЕНИЕ: {loc}: {problem}, модуль будет пустым")
            result[loc] = None
        else:
            result[loc] = names
    return result


# ---------------------------------------------------------------- запись

def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", " ")
    return '"' + s + '"'


def read_interface():
    """Номер Interface берётся из основного ItemLoc.toc, чтобы модули всегда совпадали с ним."""
    try:
        with open(os.path.join(ROOT, "ItemLoc.toc"), encoding="utf-8-sig") as f:
            for line in f:
                if line.lower().startswith("## interface:"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return "16001"


def write_module(loc, label, names, interface):
    folder = os.path.join(MODULES_DIR, f"ItemLoc_{loc}")
    os.makedirs(folder, exist_ok=True)

    with open(os.path.join(folder, f"ItemLoc_{loc}.toc"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"## Interface: {interface}\n")
        f.write(f"## Title: ItemLoc: {label} ({loc})\n")
        f.write(f"## Notes: Названия предметов для ItemLoc, язык {loc}. Загружается по требованию.\n")
        f.write("## LoadOnDemand: 1\n")
        f.write("## Dependencies: ItemLoc\n")
        f.write("## Group: ItemLoc\n")   # в списке аддонов модули сворачиваются под основным (клиент 11.1.0+)
        f.write("## Version: @project-version@\n")
        f.write("Data.lua\n")

    with open(os.path.join(folder, "Data.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("ItemLocData = ItemLocData or {}\n")
        if not names:
            f.write(f'ItemLocData["{loc}"] = {{ n = {{}}, l = {{}}, empty = true }}\n')
            return 0
        ids = sorted(i for i, n in names.items() if n)
        f.write("local n, l = {}, {}\n")
        f.write("local function run(fn) fn() end\n")
        for start in range(0, len(ids), CHUNK):
            f.write("run(function()\n")
            for item_id in ids[start:start + CHUNK]:
                name = names[item_id]
                f.write(f"n[{item_id}]={lua_str(name)}\nl[{item_id}]={lua_str(name.lower())}\n")
            f.write("end)\n")
        f.write(f'ItemLocData["{loc}"] = {{ n = n, l = l }}\n')
        return len(ids)


def copy_to_addons(locales):
    """Для разработки: если репозиторий лежит в Interface\\AddOns, копируем модули рядом."""
    addons = os.path.dirname(ROOT)
    if os.path.basename(addons).lower() != "addons":
        return
    for loc in locales:
        src = os.path.join(MODULES_DIR, f"ItemLoc_{loc}")
        dst = os.path.join(addons, f"ItemLoc_{loc}")
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(src, dst)
    print(f"Модули скопированы в {addons}")


def check_latest_build():
    """Определяет самую новую сборку Forever, для которой на wago.tools есть таблица предметов.
    Скачивает только один небольшой файл. Ничего не записывает. Печатает номер сборки."""
    with contextlib.redirect_stdout(sys.stderr):   # журнал в stderr, чтобы stdout содержал только номер
        for build in forever_build_candidates():
            try:
                parse(download(build, "enUS"))
            except urllib.error.URLError as e:
                print(f"  {build}: не получилось ({e}), пробую следующую")
                continue
            print(f"  Новейшая доступная сборка: {build}")
            break
        else:
            sys.exit("Не удалось определить сборку Forever")
    print(build)


def main():
    if "--check" in sys.argv:
        check_latest_build()
        return
    forever, forever_build = load_source("Forever", forever_build_candidates())
    era, _ = load_source("Classic Era", CLASSIC_ERA_BUILDS)
    names_by_locale = validate(merge(forever, era))

    only_era = len(set(era["enUS"]) - set(forever["enUS"]))
    print(f"Из Classic Era добавлено предметов, которых нет в Forever: {only_era}")

    # Всё проверено, теперь можно писать файлы
    shutil.rmtree(MODULES_DIR, ignore_errors=True)
    interface = read_interface()
    for loc, label in LOCALES.items():
        count = write_module(loc, label, names_by_locale[loc], interface)
        print(f"  {loc}: {count if count else 'пустой модуль'}")

    with open(os.path.join(ROOT, "Build.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"ItemLocDataBuild = {lua_str(forever_build)}\n")

    copy_to_addons(LOCALES)
    print(f"Готово: сборка Forever {forever_build}, модулей: {len(LOCALES)}")


if __name__ == "__main__":
    main()
