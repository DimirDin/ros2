# Базовый образ: Jetson Orin Nano, JetPack 7.2 (L4T r39.2), ROS2 Jazzy, CUDA 13.2.
#
# Отличия от JP6, помимо версий:
#   * rootfs — Ubuntu 24.04, поэтому ROS2 здесь Jazzy: Humble под 24.04 из apt
#     не существует (см. docs/architecture.md);
#   * второй репозиторий называется `som`, а не `t234` — в r39.2 разбивка по
#     SoC заменена на общий репозиторий модулей;
#   * поддержка Orin подтверждается пакетом cuda-compat-orin-13-2.
#
# Собирается только под linux/arm64 (нативно на ARM-раннере либо через QEMU).
FROM --platform=linux/arm64 ubuntu:24.04

ARG L4T_RELEASE=r39.2
ARG L4T_SOC=som
ARG CUDA_PKG_VERSION=13-2
ARG ROS_DISTRO=jazzy
# Модель CPU для эмуляции QEMU. Объявлена как ARG, а не ENV: значение
# доступно командам RUN во время сборки, но не остаётся в готовом образе,
# где оно бессмысленно. Пусто при нативной сборке — тогда qemu не участвует.
ARG QEMU_CPU=""

ENV ROS_DISTRO=${ROS_DISTRO} \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg && \
    curl -fsSL https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-jetson.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-jetson.gpg] https://repo.download.nvidia.com/jetson/common ${L4T_RELEASE} main" \
        > /etc/apt/sources.list.d/nvidia-l4t.list && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-jetson.gpg] https://repo.download.nvidia.com/jetson/${L4T_SOC} ${L4T_RELEASE} main" \
        >> /etc/apt/sources.list.d/nvidia-l4t.list && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-toolkit-${CUDA_PKG_VERSION} \
        cuda-compat-orin-${CUDA_PKG_VERSION} && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/install-ros2.sh /tmp/install-ros2.sh
RUN /tmp/install-ros2.sh && rm /tmp/install-ros2.sh

ENV CUDA_ARCH_DEFAULT="87" \
    PLATFORM_ID=jetson-nano-jp7 \
    L4T_RELEASE=${L4T_RELEASE} \
    JETPACK_VERSION=7.2 \
    CUDA_HOME=/usr/local/cuda
ENV PATH="${CUDA_HOME}/bin:${PATH}" \
    LD_LIBRARY_PATH="${CUDA_HOME}/lib64:/usr/lib/aarch64-linux-gnu/tegra"

COPY scripts/verify-cuda.sh /usr/local/bin/verify-cuda
RUN chmod +x /usr/local/bin/verify-cuda

SHELL ["/bin/bash", "-c"]
CMD ["bash"]
