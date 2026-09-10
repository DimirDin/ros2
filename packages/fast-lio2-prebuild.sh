#!/usr/bin/env bash
# Подготовка зависимостей FAST-LIO2 перед colcon build.
#
# Выполняется в целевом контейнере с рабочим каталогом ${WS}.
set -euxo pipefail

WS="${WS:-/opt/ros_ws}"

# --- 1. Livox-SDK2 -----------------------------------------------------------
# Пакета нет ни в apt, ни в rosdep, а livox_ros_driver2 без него не
# конфигурируется.
git clone --depth 1 https://github.com/Livox-SDK/Livox-SDK2.git /tmp/Livox-SDK2
cmake -S /tmp/Livox-SDK2 -B /tmp/Livox-SDK2/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build /tmp/Livox-SDK2/build --parallel "$(nproc)"
cmake --install /tmp/Livox-SDK2/build
ldconfig
rm -rf /tmp/Livox-SDK2

# --- 2. livox_ros_driver2 под ROS2 -------------------------------------------
# В репозитории драйвера нет package.xml: лежат package_ROS1.xml и
# package_ROS2.xml, а нужный подставляет их build.sh. Без этого шага colcon
# вообще не видит там пакета, и зависимость FAST-LIO2 остаётся неразрешённой.
# Повторяем ровно то, что делает build.sh для ветки ROS2.
DRIVER="${WS}/src/livox_ros_driver2"
if [ -d "${DRIVER}" ]; then
    cp -f "${DRIVER}/package_ROS2.xml" "${DRIVER}/package.xml"
    rm -rf "${DRIVER}/launch"
    cp -rf "${DRIVER}/launch_ROS2" "${DRIVER}/launch"
else
    echo "Не найден ${DRIVER}: проверьте vcs_file в манифесте" >&2
    exit 1
fi
