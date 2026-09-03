#!/usr/bin/env bash
# Устанавливает ROS2 (${ROS_DISTRO}) и инструменты сборки.
# Общий для всех трёх базовых образов: логика одинакова, различаются только
# кодовое имя Ubuntu и дистрибутив ROS.
set -euxo pipefail

: "${ROS_DISTRO:?ROS_DISTRO must be set}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg locales software-properties-common

# ROS2 требует UTF-8, иначе rosdep и colcon падают на не-ASCII путях.
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

add-apt-repository -y universe

UBUNTU_CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" \
    > /etc/apt/sources.list.d/ros2.list

apt-get update
apt-get install -y --no-install-recommends \
    "ros-${ROS_DISTRO}-ros-base" \
    "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" \
    build-essential cmake git ninja-build \
    python3-colcon-common-extensions \
    python3-rosdep python3-vcstool python3-pip

rosdep init
rosdep update --rosdistro "${ROS_DISTRO}"

rm -rf /var/lib/apt/lists/*
