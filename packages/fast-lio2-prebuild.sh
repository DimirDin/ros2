#!/usr/bin/env bash
# Собирает Livox-SDK2 из исходников: пакета в apt нет, ключа в rosdep тоже,
# а livox_ros_driver2 без него не конфигурируется.
set -euxo pipefail

git clone --depth 1 https://github.com/Livox-SDK/Livox-SDK2.git /tmp/Livox-SDK2
cmake -S /tmp/Livox-SDK2 -B /tmp/Livox-SDK2/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/Livox-SDK2/build --parallel "$(nproc)"
cmake --install /tmp/Livox-SDK2/build
ldconfig
rm -rf /tmp/Livox-SDK2
