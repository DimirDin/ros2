#!/usr/bin/env bash
# Локальное воспроизведение того, что делает CI. Полезно для отладки: цикл
# «правка — сборка» в GitHub Actions слишком длинный, особенно под QEMU.
#
#   scripts/build-local.sh base x86-gpu
#   scripts/build-local.sh base jetson-agx-jp6      # включит QEMU при нужде
#   scripts/build-local.sh package cuda-probe x86-gpu
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

die() { echo "Ошибка: $*" >&2; exit 1; }

query() {  # query <yaml-path> <expr>
    python3 -c "
import sys, yaml
d = yaml.safe_load(open('$1'))
print(eval('''$2''', {'d': d}))
"
}

platform_field() {  # platform_field <platform_id> <field>
    python3 -c "
import sys, yaml
ps = {p['id']: p for p in yaml.safe_load(open('platforms.yaml'))['platforms']}
p = ps.get('$1')
if p is None:
    sys.exit('неизвестная платформа: $1')
print(p.get('$2', ''))
"
}

ensure_qemu() {  # включаем binfmt, только если целевая архитектура чужая
    local target="$1"
    local host_arch host
    # Присваивание отдельной строкой: иначе код возврата docker потеряется,
    # и неподнятый демон выглядел бы как «архитектуры совпали».
    host_arch="$(docker version --format '{{.Server.Arch}}')" \
        || die "Docker недоступен: запустите демон"
    host="linux/${host_arch}"
    if [ "${target}" != "${host}" ]; then
        echo "Целевая ${target} != хостовая ${host}: включаю QEMU"
        docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
    fi
}

KIND="${1:-}"; shift || die "укажите base|package"

case "${KIND}" in
  base)
    PLATFORM="${1:?укажите платформу}"
    DOCKERFILE="$(platform_field "${PLATFORM}" dockerfile)"
    DOCKER_PLATFORM="$(platform_field "${PLATFORM}" docker_platform)"
    ROS_DISTRO="$(platform_field "${PLATFORM}" ros_distro)"
    TAG="ros2-cuda/base-${PLATFORM}:local"

    ensure_qemu "${DOCKER_PLATFORM}"
    docker buildx build \
        --platform "${DOCKER_PLATFORM}" \
        --file "${DOCKERFILE}" \
        --build-arg "ROS_DISTRO=${ROS_DISTRO}" \
        --tag "${TAG}" \
        --load .
    echo
    echo "Собрано: ${TAG}"
    docker run --rm --platform "${DOCKER_PLATFORM}" "${TAG}" verify-cuda
    ;;

  package)
    PKG="${1:?укажите пакет}"
    PLATFORM="${2:?укажите платформу}"
    MANIFEST="packages/${PKG}.yaml"
    [ -f "${MANIFEST}" ] || die "нет манифеста ${MANIFEST}"

    DOCKER_PLATFORM="$(platform_field "${PLATFORM}" docker_platform)"
    CUDA_ARCH="$(platform_field "${PLATFORM}" cuda_arch)"
    BASE="${BASE_IMAGE:-ros2-cuda/base-${PLATFORM}:local}"
    TAG="ros2-cuda/${PKG}-${PLATFORM}:local"

    get() { query "${MANIFEST}" "$1"; }

    ensure_qemu "${DOCKER_PLATFORM}"
    docker buildx build \
        --platform "${DOCKER_PLATFORM}" \
        --file templates/package.Dockerfile \
        --build-arg "BASE_IMAGE=${BASE}" \
        --build-arg "PKG_NAME=${PKG}" \
        --build-arg "REPO_URL=$(get "d.get('repo','')")" \
        --build-arg "REPO_REF=$(get "d.get('ref','main')")" \
        --build-arg "SRC_SUBDIR=$(get "d.get('src_subdir','.')")" \
        --build-arg "LOCAL_PATH=$(get "d.get('local_path','')")" \
        --build-arg "CUDA_ARCH=${CUDA_ARCH}" \
        --build-arg "APT_DEPS=$(get "' '.join(d.get('apt_deps') or [])")" \
        --build-arg "CMAKE_ARGS=$(get "' '.join(d.get('cmake_args') or [])")" \
        --build-arg "VCS_FILE=$(get "d.get('vcs_file','')")" \
        --build-arg "PRE_BUILD=$(get "d.get('pre_build','')")" \
        --build-arg "ROSDEP_SKIP_KEYS=$(get "d.get('rosdep_skip_keys','')")" \
        --tag "${TAG}" \
        --load .
    echo
    echo "Собрано: ${TAG}"
    docker run --rm --platform "${DOCKER_PLATFORM}" "${TAG}" verify-cuda
    ;;

  *) die "неизвестный режим: ${KIND} (ожидается base|package)" ;;
esac
