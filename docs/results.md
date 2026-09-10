# Результаты

Сводка того, что сделано и чем это подтверждается. Даты и статусы — на
2026-09-10.

## Что работает

### Базовые образы (требование 3.2)

Три образа собраны, опубликованы в публичном реестре и проходят проверку
наличия CUDA и работоспособности ROS2.

| Образ | Платформа | ROS2 | CUDA | Размер |
|---|---|---|---|---|
| `ghcr.io/dimirdin/ros2/base-x86-gpu` | x86_64 + NVIDIA GPU | Humble | 12.6 | 4.0 ГБ |
| `ghcr.io/dimirdin/ros2/base-jetson-agx-jp6` | AGX Orin, JetPack 6.2.2 | Humble | 12.6 | 3.4 ГБ |
| `ghcr.io/dimirdin/ros2/base-jetson-nano-jp7` | Orin Nano, JetPack 7.2 | Jazzy | 13.2 | 4.2 ГБ |

Проверить без клонирования репозитория:

```bash
docker run --rm ghcr.io/dimirdin/ros2/base-x86-gpu:latest verify-cuda
```

### Пайплайн (требования 3.5, 4)

* матрица сборки генерируется из `packages/*.yaml` — workflow не знает имён
  пакетов;
* триггеры: push в `main`, тег `v*`, ручной запуск с фильтрами, еженедельный
  cron для базовых образов;
* двухуровневый кеш слоёв: `type=gha` плюс `type=registry`;
* каждый образ после сборки проверяется на CUDA и на работоспособность ROS2;
* `validate` отсекает опечатки в манифестах до начала дорогих сборок, включая
  сетевую проверку существования веток и репозиториев.

### Подтверждение CUDA (требование 4)

Пакет `cuda_probe` содержит настоящее CUDA-ядро. После сборки `cuobjdump`
проверяет, что в бинаре присутствует код под целевую архитектуру GPU
(`sm_87` для Orin, `sm_75/86/89` для x86). Проверка падает, если кода нет.

Это ловит характерную ошибку кросс-сборки: без явного
`CMAKE_CUDA_ARCHITECTURES` CMake подставляет архитектуру сборочной машины,
сборка проходит успешно, а на Jetson не запускается ни одно ядро.

Отдельный пакет понадобился потому, что FAST-LIO2 в апстриме CUDA не
использует — это CPU-код на Eigen и PCL, и подтвердить на нём фактическую
компиляцию CUDA невозможно.

### Пример стороннего пакета (требование 4)

FAST-LIO2 собирается из апстрима без форка. Понадобились три вмешательства,
все — в `packages/fast-lio2-prebuild.sh`:

1. **Livox-SDK2** собирается из исходников: пакета нет ни в apt, ни в rosdep.
2. **`livox_ros_driver2`** приводится к виду, пригодному для ROS2. В его
   репозитории нет `package.xml` — лежат `package_ROS1.xml` и
   `package_ROS2.xml`, нужный подставляет `build.sh`. Без этого шага `colcon`
   не видит там пакета вовсе.
3. **Стандарт C++ поднимается до 17.** FAST-LIO2 прописывает `-std=c++14` в
   четырёх местах, включая `ADD_COMPILE_OPTIONS`, поэтому передать
   `-DCMAKE_CXX_STANDARD=17` снаружи невозможно. Заголовки `rclcpp` в Jazzy
   требуют C++17.

## Известные ограничения

### Кросс-сборка под JetPack 6 через QEMU

Не работает. Причина — в эмуляторе, а не в конфигурации:

```
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
IMPORTED_LOCATION not set for imported target "VTK::CommonCore"
```

QEMU падает во время установки пакетов, оставляя VTK и PCL в поломанном
состоянии. У `cuda_probe` тот же корень проявился иначе: `cudafe++` из
CUDA 12.6 сообщал о синтаксической ошибке в корректном C++ при определении
компилятора CMake.

Что установлено точно:

* тот же образ **нативно на ARM собирается без ошибок** — значит дело не в
  Dockerfile и не в зависимостях;
* JetPack 7 (Ubuntu 24.04) **через ту же эмуляцию проходит** — значит дело не
  в самой связке QEMU + arm64;
* QEMU в раннере уже последней версии (v10.2.3), обновление не поможет.

Проверенная и **отклонённая** гипотеза: предполагалось, что виноват набор
расширений эмулируемого CPU — по умолчанию QEMU включает SVE, которого нет у
бинарей Ubuntu 22.04 в обиходе. Модель ограничили до `cortex-a76` (та же
ARMv8.2, что у Orin, но без SVE). Аргумент дошёл до сборки —
`--build-arg QEMU_CPU=cortex-a76` виден в логе, — но `cudafe++` падает с той
же ошибкой. Причина не в этом.

Механизм оставлен: `qemu_cpu` задаётся в `platforms.yaml` как свойство
платформы и может пригодиться при смене версии эмулятора.

**Рабочий путь для JetPack 6 — сборка на ARM64-раннере** (способ `native-arm`).
Он зелёный, не требует физического Jetson и вдобавок в разы быстрее
эмуляции. Если кросс-сборка на x86 принципиальна, следующий шаг —
официальный кросс-компилятор NVIDIA (`cuda-cross-aarch64`), при котором
`nvcc` выполняется нативно на x86 и эмуляция обходится там, где она ломается.

### Runtime-проверка на GPU

Уровень 3 в `verify-cuda` (`nvidia-smi`, запуск ядра) требует физического
устройства. В CI пропускается: GitHub-раннеры без GPU. Job'ы для self-hosted
Jetson описаны в матрице и включаются флагом `include_self_hosted`.

## Опубликованные образы

Все публичные, доступны без авторизации:

```
ghcr.io/dimirdin/ros2/base-x86-gpu:latest
ghcr.io/dimirdin/ros2/base-jetson-agx-jp6:latest
ghcr.io/dimirdin/ros2/base-jetson-nano-jp7:latest
ghcr.io/dimirdin/ros2/cuda-probe-x86-gpu:latest
ghcr.io/dimirdin/ros2/cuda-probe-jetson-agx-jp6:latest-native-arm
ghcr.io/dimirdin/ros2/cuda-probe-jetson-nano-jp7:latest
ghcr.io/dimirdin/ros2/fast-lio2-x86-gpu:latest
ghcr.io/dimirdin/ros2/fast-lio2-jetson-agx-jp6:latest-native-arm
ghcr.io/dimirdin/ros2/fast-lio2-jetson-nano-jp7:latest-native-arm
```

Суффикс `-native-arm` означает, что канонический тег пишет способ `cross`, а
он для этой платформы не проходит; образ собран на ARM64-раннере.

## Добавление нового пакета

Один YAML-файл в `packages/`. Подробности и типовые случаи —
[docs/adding-package.md](adding-package.md).

```yaml
name: my-package
repo: https://github.com/example/my_ros2_package
ref: main
platforms: [x86-gpu, jetson-agx-jp6, jetson-nano-jp7]
```
