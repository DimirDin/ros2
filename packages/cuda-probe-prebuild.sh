#!/usr/bin/env bash
# Диагностика окружения перед сборкой. Не влияет на результат: печатает
# сведения и продолжает в любом случае.
#
# Нужна для разбора отказа кросс-сборки под JetPack 6, где cudafe++ сообщает
# о синтаксической ошибке в сгенерированном CMake файле, причём макрос
# COMPILER_ID остаётся неразвёрнутым. Проверяем по отдельности препроцессор
# и компилятор CUDA, чтобы понять, что именно ломается под эмуляцией.
# намеренно без set -e: диагностика обязана дойти до конца
set -u

echo "=============== ДИАГНОСТИКА ==============="
echo "uname:      $(uname -m)"
echo "gcc:        $(gcc --version | head -1)"
echo "nvcc:       $(nvcc --version | awk '/release/{print $5, $6}')"
echo "cmake:      $(cmake --version | head -1)"

echo
echo "--- 1. Препроцессор: разворачивается ли макрос из #if ---"
cat > /tmp/pp.c <<'SRC'
#if defined(__NVCC__)
# define COMPILER_ID "NVIDIA"
#endif
char const* info = "compiler[" COMPILER_ID "]";
SRC
if gcc -D__NVCC__ -E /tmp/pp.c -o /tmp/pp.i 2>/tmp/pp.err; then
    echo "gcc -E завершился успешно, результат:"
    tail -2 /tmp/pp.i
    if grep -q 'COMPILER_ID' /tmp/pp.i; then
        echo ">>> МАКРОС НЕ РАЗВЁРНУТ — препроцессор ведёт себя неверно"
    else
        echo ">>> макрос развёрнут правильно"
    fi
else
    echo ">>> gcc -E ЗАВЕРШИЛСЯ ОШИБКОЙ:"; cat /tmp/pp.err
fi

echo
echo "--- 2. Компиляция простейшего CUDA-ядра ---"
cat > /tmp/k.cu <<'SRC'
__global__ void k(float* a) { a[threadIdx.x] += 1.0f; }
SRC
if nvcc -arch=sm_87 -c /tmp/k.cu -o /tmp/k.o 2>/tmp/k.err; then
    echo ">>> nvcc собрал ядро успешно"
    cuobjdump /tmp/k.o 2>/dev/null | grep -oE 'sm_[0-9]+' | sort -u | sed 's/^/    код под /'
else
    echo ">>> nvcc ЗАВЕРШИЛСЯ ОШИБКОЙ:"; head -20 /tmp/k.err
fi
echo "==========================================="
exit 0
