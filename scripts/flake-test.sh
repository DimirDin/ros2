#!/usr/bin/env bash
# Измеряет частоту плавающих отказов одной комбинации сборки.
#
# Запускает N независимых прогонов workflow `packages` с отключённым кешем и
# считает, сколько прошло. Без --no-cache измерение бессмысленно: успешный
# прогон записывает слои в buildcache, и следующие берут готовое, не выполняя
# сборку вообще.
#
# Прогоны идут параллельно: ручные запуски получают уникальную группу
# concurrency и не отменяют друг друга.
#
#   scripts/flake-test.sh 8 cuda-probe jetson-agx-jp6 cross
set -euo pipefail

RUNS="${1:?сколько прогонов}"
PKG="${2:?пакет}"
PLATFORM="${3:?платформа}"
METHOD="${4:?способ сборки}"

command -v gh >/dev/null || { echo "нужен gh" >&2; exit 1; }

echo "Замер: ${PKG} / ${PLATFORM} / ${METHOD}, прогонов: ${RUNS}, кеш отключён"
echo

ids=()
for i in $(seq 1 "${RUNS}"); do
    gh workflow run packages.yml \
        -f packages="${PKG}" \
        -f platforms="${PLATFORM}" \
        -f methods="${METHOD}" \
        -f no_cache=true >/dev/null
    # Идентификатор появляется не мгновенно; забираем свежайший прогон,
    # которого ещё нет в списке собранных.
    for _ in $(seq 1 20); do
        sleep 3
        id="$(gh run list --workflow=packages.yml --event=workflow_dispatch \
              --limit 1 --json databaseId --jq '.[0].databaseId')"
        case " ${ids[*]-} " in *" ${id} "*) continue ;; esac
        ids+=("${id}")
        echo "  запуск ${i}/${RUNS}: ${id}"
        break
    done
done

echo
echo "Ожидание завершения..."
for id in "${ids[@]}"; do
    while :; do
        st="$(gh run view "${id}" --json status --jq .status)"
        [ "${st}" = "completed" ] && break
        sleep 20
    done
done

echo
ok=0; fail=0
for id in "${ids[@]}"; do
    concl="$(gh run view "${id}" --json conclusion --jq .conclusion)"
    if [ "${concl}" = "success" ]; then ok=$((ok+1)); else fail=$((fail+1)); fi
    printf "  %-12s %s\n" "${concl}" "${id}"
done

echo
echo "Итог: успешно ${ok} из ${RUNS}, отказов ${fail}"
awk -v o="${ok}" -v n="${RUNS}" 'BEGIN{printf "Доля успешных: %.0f%%\n", 100*o/n}'
