#!/usr/bin/env bash
# Решает, нужно ли выпускать новую версию. Результат пишет в $GITHUB_OUTPUT (changed=true|false).
# Переменные окружения: NEW_BUILD (новейшая сборка Forever), FORCE (true/false).
# Запускать из корня репозитория.
set -u
old_build=$(tr -d '[:space:]' < data_build.txt 2>/dev/null || true)
old_build=${old_build:-0}
changed=false

if [ "$NEW_BUILD" != "$old_build" ]; then
  echo "Новая сборка данных: $old_build -> $NEW_BUILD"
  changed=true
fi
if ! git diff --quiet -- Polyglot.toc; then
  echo "Изменился номер Interface:"
  git diff -- Polyglot.toc
  changed=true
fi
if [ "${FORCE:-false}" = "true" ]; then
  echo "Принудительный выпуск"
  changed=true
fi

# Защита от бесконечных повторов: если предыдущая версия до сих пор не опубликована
# (запуск Release упал или ещё идёт), ждём 72 часа, прежде чем пробовать снова.
if [ "$changed" = true ] && [ "${FORCE:-false}" != "true" ]; then
  last=$(git tag --list 'v*' --sort=-v:refname | head -n 1)
  if [ -n "$last" ] && ! gh release view "$last" >/dev/null 2>&1; then
    created=$(git for-each-ref --format='%(creatordate:unix)' "refs/tags/$last")
    age_h=$(( ( $(date +%s) - created ) / 3600 ))
    if [ "$age_h" -lt 72 ]; then
      echo "::warning::Версия $last ещё не опубликована (прошло $age_h ч). Новый выпуск пропущен, проверьте запуск Release."
      changed=false
    fi
  fi
fi

echo "changed=$changed" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "Итог: changed=$changed"
