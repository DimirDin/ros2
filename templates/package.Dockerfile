# syntax=docker/dockerfile:1.7
#
# Универсальный шаблон сборки ROS2-пакета (требование 3.3 ТЗ).
#
# Один файл на все пакеты и все платформы. Всё, что специфично для пакета,
# приходит аргументами из packages/<name>.yaml; всё, что специфично для
# платформы, — из BASE_IMAGE и CUDA_ARCH. Добавление нового пакета не требует
# правок ни здесь, ни в workflow.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG PKG_NAME
# Источник исходников. Пусто — значит пакет лежит в этом репозитории и берётся
# из build-контекста (LOCAL_PATH), а не клонируется по сети.
ARG REPO_URL=""
ARG REPO_REF=main
# Подкаталог внутри клонированного репозитория, содержащий ROS2-пакет(ы).
ARG SRC_SUBDIR=.
# Путь пакета внутри каталога src/ этого репозитория. Используется, когда
# REPO_URL пуст. Клонировать собственный репозиторий по сети было бы лишним
# кругом и привязкой к его имени и к тому, что коммит уже запушен.
ARG LOCAL_PATH=""
# Список архитектур GPU для CMAKE_CUDA_ARCHITECTURES, например "87".
# Пусто по умолчанию: тогда берётся CUDA_ARCH_DEFAULT из базового образа.
# Отдельное имя нужно потому, что ARG затеняет одноимённую ENV пустым значением.
ARG CUDA_ARCH=""
# Пакеты apt, которых нет в rosdep (через пробел).
ARG APT_DEPS=""
# Имя необязательного .repos-файла в каталоге packages/ (только имя файла).
ARG VCS_FILE=""
# Ключи rosdep, которые нужно пропустить (например, отсутствующие в индексе).
ARG ROSDEP_SKIP_KEYS=""
# Имя необязательного скрипта в packages/, выполняемого перед colcon build.
# Нужен для зависимостей, которых нет ни в apt, ни в rosdep и которые надо
# собрать из исходников (например, Livox-SDK2 для FAST-LIO2).
ARG PRE_BUILD=""
# Дополнительные аргументы CMake (через пробел).
ARG CMAKE_ARGS=""
ARG WS=/opt/ros_ws

ENV DEBIAN_FRONTEND=noninteractive \
    WS=${WS} \
    PKG_NAME=${PKG_NAME}

SHELL ["/bin/bash", "-c"]

# Системные зависимости объявляются отдельным слоем: они меняются реже
# исходников, поэтому переживают перестройку при новом коммите пакета.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    if [ -n "${APT_DEPS}" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends ${APT_DEPS} && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "APT_DEPS пуст — шаг пропущен"; \
    fi

WORKDIR ${WS}/src

# Локальные исходники кладём отдельным слоем: он меняется при каждой правке
# кода, поэтому стоит ниже установки зависимостей.
COPY src/ /tmp/local-src/

RUN if [ -n "${REPO_URL}" ]; then \
        echo "Источник: git ${REPO_URL}@${REPO_REF}" && \
        git clone --depth 1 --branch "${REPO_REF}" --recurse-submodules \
            "${REPO_URL}" "${PKG_NAME}-checkout" && \
        if [ "${SRC_SUBDIR}" != "." ]; then \
            mv "${PKG_NAME}-checkout/${SRC_SUBDIR}" "./${PKG_NAME}"; \
            rm -rf "${PKG_NAME}-checkout"; \
        else \
            mv "${PKG_NAME}-checkout" "./${PKG_NAME}"; \
        fi && \
        rm -rf "./${PKG_NAME}/.git"; \
    elif [ -n "${LOCAL_PATH}" ]; then \
        echo "Источник: build-контекст, src/${LOCAL_PATH}" && \
        test -d "/tmp/local-src/${LOCAL_PATH}" \
            || { echo "Нет каталога src/${LOCAL_PATH} в контексте сборки" >&2; exit 1; } && \
        cp -r "/tmp/local-src/${LOCAL_PATH}" "./${PKG_NAME}"; \
    else \
        echo "Не задан ни REPO_URL, ни LOCAL_PATH" >&2; exit 1; \
    fi && \
    rm -rf /tmp/local-src

# Каталог манифестов копируется целиком: COPY не умеет условных путей,
# а весит он килобайты.
COPY packages/ /tmp/packages/
RUN if [ -n "${VCS_FILE}" ] && [ -s "/tmp/packages/${VCS_FILE}" ]; then \
        vcs import . < "/tmp/packages/${VCS_FILE}"; \
    else \
        echo "VCS_FILE не задан — дополнительных исходников нет"; \
    fi && \
    rm -rf /tmp/packages

WORKDIR ${WS}

COPY packages/ /tmp/prebuild/
RUN if [ -n "${PRE_BUILD}" ]; then \
        echo "Выполняется pre-build: ${PRE_BUILD}" && \
        bash "/tmp/prebuild/${PRE_BUILD}"; \
    else \
        echo "PRE_BUILD не задан — шаг пропущен"; \
    fi && \
    rm -rf /tmp/prebuild

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
    apt-get update && \
    rosdep install --from-paths src --ignore-src -y \
        --rosdistro "${ROS_DISTRO}" \
        --skip-keys "${ROSDEP_SKIP_KEYS:-}" && \
    rm -rf /var/lib/apt/lists/*

# Ключевой шаг: CMAKE_CUDA_ARCHITECTURES задаётся явно. Без него CMake
# подставит архитектуру сборочной машины — при кросс-компиляции это даёт
# бинарь, который на целевом Jetson молча не запустит ни одного ядра.
RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" && \
    export CUDA_ARCH="${CUDA_ARCH:-${CUDA_ARCH_DEFAULT}}" && \
    echo "Сборка ${PKG_NAME} под CUDA-архитектуры: ${CUDA_ARCH}" && \
    colcon build \
        --merge-install \
        --cmake-args \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
            ${CMAKE_ARGS} \
        --event-handlers console_direct+ && \
    rm -rf build/*/CMakeFiles

RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -e' \
    'source /opt/ros/${ROS_DISTRO}/setup.bash' \
    'source ${WS}/install/setup.bash' \
    'exec "$@"' > /ros_entrypoint.sh && \
    chmod +x /ros_entrypoint.sh

LABEL org.opencontainers.image.title="${PKG_NAME}" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${REPO_REF}" \
      ros.distro="${ROS_DISTRO}" \
      cuda.architectures="${CUDA_ARCH}"

# Пробрасываем фактическую архитектуру в окружение образа, чтобы
# verify-cuda мог сверить её с содержимым собранного бинаря.
ENV CUDA_ARCH=${CUDA_ARCH}

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
