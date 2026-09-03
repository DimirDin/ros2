# ros2-cuda-crossbuild

Кросс-платформенная сборка Docker-образов для ROS2-пакетов с поддержкой CUDA.


Один манифест на пакет — образы под три платформы, собранные нативно и
кросс-платформенно, с проверкой того, что CUDA действительно применена.

## Платформы

| id | Устройство | JetPack / L4T | Ubuntu | ROS2 | CUDA | `sm_` |
|---|---|---|---|---|---|---|
| `x86-gpu` | x86_64 + NVIDIA GPU | — | 22.04 | Humble | 12.6 | 75, 86, 89 |
| `jetson-agx-jp6` | Jetson AGX Orin 64GB | 6.2.2 / r36.5 | 22.04 | Humble | 12.6 | 87 |
| `jetson-nano-jp7` | Jetson Orin Nano | 7.2 / r39.2 | 24.04 | Jazzy | 13.2 | 87 |

На JetPack 7 используется Jazzy, а не Humble: JP7 построен на Ubuntu 24.04,
под которую Humble не выпускался. Подробности — в
[docs/architecture.md](docs/architecture.md).

## Способы сборки

| Способ | Раннер | Эмуляция | GPU |
|---|---|---|---|
| `native` (x86) | `ubuntu-22.04` | нет | нет |
| `cross` | `ubuntu-22.04` + QEMU | да | нет |
| `native-arm` | `ubuntu-24.04-arm` | нет | нет |
| `native` (Jetson) | self-hosted Jetson | нет | да |

## Готовые образы

```bash
# базовый образ
docker pull ghcr.io/<owner>/<repo>/base-jetson-agx-jp6:latest

# FAST-LIO2, собранный под AGX Orin
docker pull ghcr.io/<owner>/<repo>/fast-lio2-jetson-agx-jp6:latest

# проверка CUDA внутри образа
docker run --rm ghcr.io/<owner>/<repo>/cuda-probe-x86-gpu:latest verify-cuda
```

## Добавление пакета

Один файл:

```yaml
# packages/my-package.yaml
name: my-package
repo: https://github.com/example/my_ros2_package
ref: main
platforms: [x86-gpu, jetson-agx-jp6, jetson-nano-jp7]
```

Коммит в `main` — образы под все платформы собраны и опубликованы.
Подробнее — [docs/adding-package.md](docs/adding-package.md).

## Структура

```
platforms.yaml               реестр целевых платформ
base/                        три базовых Dockerfile (ROS2 + CUDA)
templates/package.Dockerfile универсальный шаблон сборки пакета
packages/                    манифесты пакетов — по одному YAML на пакет
src/cuda_probe/              ROS2-пакет с CUDA-ядром для проверки сборки
scripts/
  generate-matrix.py         матрица CI из платформ и манифестов
  install-ros2.sh            установка ROS2, общая для трёх баз
  verify-cuda.sh             трёхуровневая проверка CUDA
  build-local.sh             локальное воспроизведение сборки
  validate.py                проверка согласованности конфигурации
.github/workflows/           validate.yml, base-images.yml, packages.yml
docs/                        архитектура, развёртывание, добавление пакета
```

## Документация

* [Архитектура](docs/architecture.md) — различия платформ, почему приняты
  именно такие решения
* [Развёртывание](docs/deployment.md) — установка пайплайна с нуля,
  подключение Jetson-раннера, диагностика
* [Добавление пакета](docs/adding-package.md) — типовые случаи с примерами
* [Проверка CUDA](docs/cuda-verification.md) — что и как подтверждается
* [Проектное решение](docs/design.md) — задача, установленные факты, границы

## Лицензия

Apache-2.0
