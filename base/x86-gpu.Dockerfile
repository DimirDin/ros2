# Базовый образ: x86_64 + NVIDIA GPU, ROS2 Humble, CUDA 12.6.
#
# Здесь всё просто: NVIDIA публикует готовые devel-образы под x86, поэтому
# CUDA приходит из базового образа, а мы добавляем только ROS2.
ARG CUDA_VERSION=12.6.3
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}

ARG ROS_DISTRO=humble
ENV ROS_DISTRO=${ROS_DISTRO} \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

COPY scripts/install-ros2.sh /tmp/install-ros2.sh
RUN /tmp/install-ros2.sh && rm /tmp/install-ros2.sh

# Значение по умолчанию для CMAKE_CUDA_ARCHITECTURES: Turing, Ampere, Ada.
# Перекрывается аргументом сборки конкретного пакета.
ENV CUDA_ARCH_DEFAULT="75;86;89" \
    PLATFORM_ID=x86-gpu \
    CUDA_HOME=/usr/local/cuda
ENV PATH="${CUDA_HOME}/bin:${PATH}"

COPY scripts/verify-cuda.sh /usr/local/bin/verify-cuda
RUN chmod +x /usr/local/bin/verify-cuda

SHELL ["/bin/bash", "-c"]
CMD ["bash"]
