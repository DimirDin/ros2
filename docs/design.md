# Кросс-платформенная сборка Docker-образов ROS2 + CUDA

Дата: 2026-09-03
Статус: утверждён

## Задача

CI/CD-система, собирающая Docker-образы ROS2-пакетов с поддержкой CUDA под три
платформы: x86_64 с NVIDIA GPU, Jetson AGX Orin (JetPack 6.2.2) и Jetson Orin
Nano (JetPack 7). Сборка — нативная и кросс-платформенная. Публикация в ghcr.io.
Добавление нового пакета должно требовать минимальных изменений.

## Установленные факты

Проверено обращением к репозиториям NVIDIA 2026-09-03:

| Параметр | JetPack 6.2.2 | JetPack 7.2 |
|---|---|---|
| Jetson Linux (L4T) | r36.5 | r39.2 |
| apt-репозитории | `common`, `t234` | `common`, `som` |
| CUDA | 12.6 | 13.2 |
| Rootfs | Ubuntu 22.04 | Ubuntu 24.04 |
| ROS2 из apt | Humble | Jazzy |

Поддержка Orin в JetPack 7 подтверждена наличием пакета `cuda-compat-orin-13-2`
в репозитории `common/r39.2`.

Официальный образ `nvcr.io/nvidia/l4t-jetpack` опубликован только до тега
`r36.4.0` (ноябрь 2024). Образов под r36.5 и r39.2 в NGC нет. Поэтому обе
Jetson-базы собираются из `ubuntu:22.04` / `ubuntu:24.04` плюс официальные
apt-репозитории NVIDIA с пином на нужный релиз L4T.

## Решения

### ROS2 на JetPack 7

Humble собран под Ubuntu 22.04; JetPack 7 построен на 24.04, где из
`packages.ros.org` доступен Jazzy. Сборка Humble из исходников на 24.04
непропорционально дорога и хрупка. Решение: на JP7 используется ROS2 Jazzy.
Шаблон сборки пакетов ROS-агностичен через `ARG ROS_DISTRO`, поэтому
манифест пакета не зависит от дистрибутива ROS.

### Платформы

| ID | База | ОС | ROS2 | CUDA | CUDA_ARCH |
|---|---|---|---|---|---|
| `x86-gpu` | `nvidia/cuda:12.6.3-devel-ubuntu22.04` | 22.04 | humble | 12.6 | 75;86;89 |
| `jetson-agx-jp6` | `ubuntu:22.04` + L4T r36.5 | 22.04 | humble | 12.6 | 87 |
| `jetson-nano-jp7` | `ubuntu:24.04` + L4T r39.2 | 24.04 | jazzy | 13.2 | 87 |

AGX Orin и Orin Nano имеют одинаковую compute capability (8.7). Платформы
различаются версией JetPack, а не архитектурой GPU.

### Способы сборки

| Платформа | native | native-arm | cross (QEMU) |
|---|---|---|---|
| `x86-gpu` | `ubuntu-22.04` | — | — |
| `jetson-agx-jp6` | self-hosted Jetson | `ubuntu-24.04-arm` | `ubuntu-22.04` + binfmt |
| `jetson-nano-jp7` | self-hosted Jetson | `ubuntu-24.04-arm` | `ubuntu-22.04` + binfmt |

`native-arm` использует бесплатные ARM64-раннеры GitHub: настоящая нативная
компиляция без эмуляции, но без GPU. `native` на self-hosted Jetson даёт
дополнительно runtime-проверку на GPU; job написан, но пропускается, пока
раннер с меткой `jetson` не зарегистрирован.

Кросс-сборка реализована через `docker buildx` + `tonistiigi/binfmt` (QEMU).
Рассматривался официальный путь NVIDIA — `cuda-cross-aarch64` с sysroot на
x86-хосте. Отвергнут: он рассчитан на CMake-проекты с явным toolchain-файлом и
плохо совмещается с `colcon` и `rosdep`, которым нужен полноценный
целевой rootfs.

### Универсальный шаблон

`templates/package.Dockerfile` принимает аргументы `BASE_IMAGE`, `REPO_URL`,
`REPO_REF`, `SRC_SUBDIR`, `CUDA_ARCH`, `ROS_DISTRO`, `APT_DEPS`, `VCS_REPOS`,
`CMAKE_ARGS`. Все параметры конкретного пакета живут в `packages/<name>.yaml`.
Добавление пакета — создание одного YAML-файла; ни Dockerfile, ни workflow
не изменяются.

### Подтверждение CUDA

Три уровня:

1. Статический — `nvcc --version`, наличие `libcudart`, `CMAKE_CUDA_COMPILER`
   в `CMakeCache.txt`. Выполняется для всех образов.
2. Компиляционный — пакет `cuda_probe` с CUDA-ядром; `cuobjdump` подтверждает
   наличие кода `sm_87` в собранном бинаре. Доказывает, что кросс-компиляция
   CUDA действительно произошла, и не требует GPU.
3. Runtime — `nvidia-smi` и запуск ядра. Только на self-hosted раннере.

Второй уровень нужен потому, что FAST-LIO2 и FAST-LIVO2 в апстриме CUDA не
используют: это CPU-код на Eigen и PCL. Без собственного CUDA-пакета
требование «подтверждение наличия CUDA» подтверждалось бы только наличием
файлов в образе.

Особенность L4T: `libcuda.so` и библиотеки Tegra не входят в образ, их
подмонтирует `nvidia-container-runtime` на устройстве. Скрипт проверки
различает «отсутствует в образе» и «ожидается от рантайма», иначе тесты
ложно краснеют.

### CI/CD

`base-images.yml` — push в `base/**`, `workflow_dispatch`, еженедельный cron.
`packages.yml` — push в `main`, теги `v*`, `workflow_dispatch`; матрица
генерируется из `packages/*.yaml` через `fromJSON`.

Теги образов: `main`, `sha-<short>`, `v<semver>`, `latest` (только с тега).
Кеш: `type=gha` плюс `type=registry` — критично для QEMU-сборок.

## Порядок реализации

1. Базовые образы и `cuda_probe` — быстрый зелёный пайплайн и прогретый кеш.
2. FAST-LIO2 как обычный манифест — демонстрация расширяемости.
3. Документация.

## Границы

Не входит: рантайм-тесты на физическом Jetson (нет железа), сборка PCL и
OpenCV с CUDA из исходников (часы под QEMU при незначительной пользе для
целевого пакета), поддержка ROS1 и JetPack 5.
