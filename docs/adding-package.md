# Добавление нового ROS2-пакета

Добавление пакета — это создание одного YAML-файла в `packages/`.
Ни `templates/package.Dockerfile`, ни workflow'ы править не нужно: матрица
сборки генерируется из содержимого каталога `packages/`.

## Минимальный случай

Пакет, у которого все зависимости разрешаются через `rosdep`:

```yaml
# packages/my-package.yaml
name: my-package
description: Краткое описание
repo: https://github.com/example/my_ros2_package
ref: main
platforms: [x86-gpu, jetson-agx-jp6, jetson-nano-jp7]
```

Коммит в `main` — и пайплайн соберёт образы под все перечисленные платформы
всеми доступными способами.

## Полный набор полей

Источник исходников задаётся ровно одним из двух полей: `repo` для внешнего
git-репозитория либо `local_path` для пакета, лежащего в этом репозитории.
Указать оба или ни одного — ошибка, её ловит `scripts/validate.py`.

| Поле | Обязательное | Назначение |
|---|---|---|
| `name` | да | имя пакета; входит в имя образа |
| `repo` | одно из двух | URL внешнего git-репозитория |
| `local_path` | одно из двух | путь пакета внутри `src/` этого репозитория |
| `ref` | нет (`main`) | ветка или тег; только с `repo` |
| `src_subdir` | нет (`.`) | подкаталог с ROS2-пакетом внутри клона; только с `repo` |
| `platforms` | да | список id из `platforms.yaml` |
| `apt_deps` | нет | пакеты apt, которых нет в rosdep |
| `vcs_file` | нет | имя `.repos`-файла в `packages/` с доп. исходниками |
| `pre_build` | нет | имя скрипта в `packages/`, выполняемого до `colcon build` |
| `rosdep_skip_keys` | нет | ключи, которые rosdep должен пропустить |
| `cmake_args` | нет | дополнительные аргументы CMake |

### Пакет живёт в этом же репозитории

```yaml
name: my-package
local_path: my_package     # то есть src/my_package
platforms: [x86-gpu]
```

Исходники берутся из build-контекста, без обращения к сети. Это быстрее и,
что важнее, не требует, чтобы текущий коммит был уже запушен: сборка
собирает ровно то, что лежит в рабочем каталоге. Рабочий пример —
`packages/cuda-probe.yaml`.

## Типовые ситуации

### Зависимость есть в apt, но не в rosdep

```yaml
apt_deps: [libpcl-dev, libeigen3-dev]
```

### Зависимость — другой ROS2-пакет из git

Создайте `packages/my-package.repos`:

```yaml
repositories:
  some_driver:
    type: git
    url: https://github.com/example/some_driver.git
    version: main
```

и сошлитесь на него:

```yaml
vcs_file: my-package.repos
rosdep_skip_keys: some_driver   # иначе rosdep не найдёт ключ и упадёт
```

### Зависимость нужно собрать из исходников

Например, SDK, которого нет ни в apt, ни в rosdep. Создайте
`packages/my-package-prebuild.sh` и укажите:

```yaml
pre_build: my-package-prebuild.sh
```

Скрипт выполняется в целевом контейнере до `colcon build`. Рабочий пример —
`packages/fast-lio2-prebuild.sh`, собирающий Livox-SDK2.

### Пакет использует CUDA

Ничего специального делать не нужно: шаблон всегда передаёт
`-DCMAKE_CUDA_ARCHITECTURES` со значением для целевой платформы. В
`CMakeLists.txt` пакета достаточно обычного `find_package(CUDAToolkit)` или
`project(... LANGUAGES CXX CUDA)`.

Не задавайте `CMAKE_CUDA_ARCHITECTURES` внутри пакета жёстко. При кросс-сборке
CMake по умолчанию подставит архитектуру сборочной машины, и получится бинарь,
который на Jetson молча не запустит ни одного ядра. Пример правильной
обработки — `src/cuda_probe/CMakeLists.txt`, где отсутствие значения приводит
к явной ошибке конфигурации, а не к тихой подстановке неверного.

### Пакет собирается не под все платформы

Уберите лишние id из `platforms`. Например, пакет, требующий Humble:

```yaml
platforms: [x86-gpu, jetson-agx-jp6]   # без jetson-nano-jp7 (там Jazzy)
```

## Проверка до коммита

Матрица, которая получится:

```bash
python3 scripts/generate-matrix.py packages --packages my-package
```

Локальная сборка одной комбинации (нужен Docker):

```bash
scripts/build-local.sh base x86-gpu
scripts/build-local.sh package my-package x86-gpu
```

Локальная сборка под ARM64 на x86-машине включит QEMU автоматически.

## Результат

Образы публикуются как:

```
ghcr.io/<owner>/<repo>/<name>-<platform>:latest
```

например `ghcr.io/<owner>/<repo>/fast-lio2-jetson-agx-jp6:latest`.
