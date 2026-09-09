#!/usr/bin/env bash
# Подтверждение наличия CUDA в образе (требование 4 ТЗ).
#
# Три уровня проверки, от дешёвого к убедительному:
#   1. static  — CUDA Toolkit присутствует и пригоден к сборке;
#   2. compile — в собранных бинарях есть код под целевую архитектуру GPU;
#   3. runtime — GPU реально доступен (только на устройстве с GPU).
#
# Уровни 1-2 не требуют GPU и потому выполняются для кросс-собранных
# arm64-образов на x86-раннере. Уровень 3 пропускается, если GPU нет.
#
# Важно про L4T: libcuda.so и библиотеки Tegra НЕ входят в Jetson-образ —
# их подмонтирует nvidia-container-runtime на устройстве. Их отсутствие
# на сборочной машине не является ошибкой, и скрипт это различает.
set -uo pipefail

FAIL=0
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }
skip()  { printf '  \033[33m—\033[0m %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"

# Login-шелл (bash -l) выполняет /etc/profile, а тот в Ubuntu перезаписывает
# PATH дефолтным значением, выбрасывая ${CUDA_HOME}/bin из ENV образа.
# Поэтому не полагаемся на унаследованный PATH, а дописываем каталог сами.
case ":${PATH}:" in
    *":${CUDA_HOME}/bin:"*) ;;
    *) PATH="${CUDA_HOME}/bin:${PATH}" ;;
esac
export PATH
EXPECTED_ARCH="${CUDA_ARCH:-${CUDA_ARCH_DEFAULT:-}}"
WS="${1:-/opt/ros_ws}"

head_ "Платформа"
echo "  PLATFORM_ID=${PLATFORM_ID:-<не задан>}  ROS_DISTRO=${ROS_DISTRO:-<не задан>}"
echo "  target arch=$(uname -m)  CUDA_ARCH=${EXPECTED_ARCH:-<не задан>}"

# --- Уровень 1: статическая проверка -----------------------------------------
head_ "1. Статическая проверка CUDA Toolkit"

if command -v nvcc >/dev/null 2>&1; then
    ok "nvcc: $(nvcc --version | awk '/release/{print $5, $6}' | tr -d ',')"
else
    fail "nvcc не найден (искали в PATH и ${CUDA_HOME}/bin)"
fi

if find "${CUDA_HOME}" /usr/local /usr/lib -name 'libcudart.so*' -print -quit 2>/dev/null | grep -q .; then
    ok "libcudart присутствует в образе"
else
    fail "libcudart не найдена"
fi

# libcuda.so — драйверная библиотека. В L4T-образе её быть не должно.
if find /usr/lib /usr/local -name 'libcuda.so*' -print -quit 2>/dev/null | grep -q .; then
    ok "libcuda присутствует (драйвер доступен)"
else
    case "${PLATFORM_ID:-}" in
        jetson-*) skip "libcuda отсутствует — ожидаемо для L4T, её монтирует nvidia-container-runtime" ;;
        *)        skip "libcuda отсутствует — нормально для devel-образа без GPU" ;;
    esac
fi

# --- Уровень 2: компиляционная проверка --------------------------------------
head_ "2. Компиляционная проверка"

PROBE_BIN="$(find "${WS}/install" -type f -name 'cuda_probe_node' 2>/dev/null | head -1)"

if [ -z "${PROBE_BIN}" ]; then
    skip "cuda_probe_node не собран в ${WS} — проверка пропущена"
else
    ok "бинарь найден: ${PROBE_BIN}"

    if ldd "${PROBE_BIN}" 2>/dev/null | grep -q 'libcudart'; then
        ok "бинарь слинкован с libcudart"
    else
        fail "бинарь не слинкован с CUDA runtime"
    fi

    # Главное доказательство: в бинаре лежит скомпилированный GPU-код.
    # Именно это отличает «CUDA лежит в образе» от «CUDA реально применена».
    if command -v cuobjdump >/dev/null 2>&1; then
        ARCHS="$(cuobjdump "${PROBE_BIN}" 2>/dev/null \
                 | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')"
        if [ -n "${ARCHS}" ]; then
            ok "GPU-код в бинаре: ${ARCHS}"
            for a in ${EXPECTED_ARCH//;/ }; do
                if echo "${ARCHS}" | grep -q "sm_${a}"; then
                    ok "целевая архитектура sm_${a} присутствует"
                else
                    fail "целевая архитектура sm_${a} ОТСУТСТВУЕТ в бинаре"
                fi
            done
        else
            fail "cuobjdump не нашёл GPU-кода в бинаре"
        fi
    else
        skip "cuobjdump недоступен"
    fi

    CACHE="$(find "${WS}" -name CMakeCache.txt -path '*cuda_probe*' 2>/dev/null | head -1)"
    if [ -n "${CACHE}" ] && grep -q '^CMAKE_CUDA_COMPILER:' "${CACHE}"; then
        ok "CMake использовал CUDA-компилятор: $(grep '^CMAKE_CUDA_COMPILER:' "${CACHE}" | cut -d= -f2)"
    fi
fi

# --- Уровень 3: runtime ------------------------------------------------------
head_ "3. Runtime-проверка (нужен GPU)"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    ok "GPU доступен: $(nvidia-smi -L | head -1)"
    if [ -n "${PROBE_BIN}" ]; then
        # shellcheck disable=SC1091
        source "${WS}/install/setup.bash" 2>/dev/null || true
        if "${PROBE_BIN}" --selftest; then
            ok "CUDA-ядро выполнено на GPU"
        else
            fail "запуск CUDA-ядра завершился ошибкой"
        fi
    fi
else
    skip "GPU не обнаружен — уровень 3 пропущен (ожидаемо при кросс-сборке)"
fi

head_ "Итог"
if [ "${FAIL}" -eq 0 ]; then
    printf '  \033[32mВсе выполненные проверки пройдены\033[0m\n\n'
else
    printf '  \033[31mЕсть непройденные проверки\033[0m\n\n'
fi
exit "${FAIL}"
