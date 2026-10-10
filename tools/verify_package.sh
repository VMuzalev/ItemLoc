#!/usr/bin/env bash
# Проверяет собранный архив: есть ли основной аддон, все модули языков и нет ли лишнего.
# Использование: tools/verify_package.sh путь/к/архиву.zip
set -u
zip="$1"
listing=$(unzip -l "$zip")
fail=0
err() { echo "::error::$1"; fail=1; }
has() { echo "$listing" | grep -qE "[[:space:]]$1\$"; }

for f in Polyglot/Polyglot.toc Polyglot/Polyglot.lua Polyglot/Build.lua; do
  has "$f" || err "В архиве нет $f"
done

modules=$(grep -oP '^\s+Polyglot/Modules/\K[^:]+' .pkgmeta)
count=0
for m in $modules; do
  count=$((count + 1))
  has "$m/$m.toc"  || err "В архиве нет $m/$m.toc (модуль не вынесен на верхний уровень?)"
  has "$m/Data.lua" || err "В архиве нет $m/Data.lua"
done
[ "$count" -gt 0 ] || err "В .pkgmeta не найдено ни одного модуля"

echo "$listing" | grep -qE "[[:space:]]Polyglot/Modules/.*Data\.lua\$" \
  && err "Модули остались внутри Polyglot/Modules и не вынесены на верхний уровень"
for extra in tools tests docs .github; do
  echo "$listing" | grep -qE "[[:space:]]Polyglot/$extra/" && err "Папка $extra попала в архив"
done

if [ "$fail" -eq 0 ]; then
  echo "Архив в порядке: основной аддон и модулей языков: $count"
fi
exit "$fail"
