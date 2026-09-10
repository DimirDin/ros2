# Базовый образ: Jetson AGX Orin, JetPack 6.2.2 (L4T r36.5), ROS2 Humble, CUDA 12.6.
#
# NGC не публикует l4t-jetpack новее r36.4.0, поэтому базу собираем сами из
# ubuntu:22.04 плюс официальные apt-репозитории NVIDIA с пином на r36.5 —
# ровно те же источники, из которых собраны образы самой NVIDIA.
#
# Собирается только под linux/arm64 (нативно на ARM-раннере либо через QEMU).
FROM --platform=linux/arm64 ubuntu:22.04

ARG L4T_RELEASE=r36.5
ARG L4T_SOC=t234
ARG CUDA_PKG_VERSION=12-6
ARG ROS_DISTRO=humble
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

# Пакеты nvidia-l4t-* сознательно не ставим: их postinst рассчитан на реальный
# rootfs Tegra и в контейнере не отрабатывает. Для сборки достаточно
# CUDA Toolkit; библиотеки времени выполнения (libcuda.so и прочие Tegra)
# подмонтирует nvidia-container-runtime на устройстве.
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-toolkit-${CUDA_PKG_VERSION} && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/install-ros2.sh /tmp/install-ros2.sh
RUN /tmp/install-ros2.sh && rm /tmp/install-ros2.sh

# Orin (AGX и Nano) — compute capability 8.7.
ENV CUDA_ARCH_DEFAULT="87" \
    PLATFORM_ID=jetson-agx-jp6 \
    L4T_RELEASE=${L4T_RELEASE} \
    JETPACK_VERSION=6.2.2 \
    CUDA_HOME=/usr/local/cuda
ENV PATH="${CUDA_HOME}/bin:${PATH}" \
    LD_LIBRARY_PATH="${CUDA_HOME}/lib64:/usr/lib/aarch64-linux-gnu/tegra"

COPY scripts/verify-cuda.sh /usr/local/bin/verify-cuda
RUN chmod +x /usr/local/bin/verify-cuda

SHELL ["/bin/bash", "-c"]
CMD ["bash"]
