cmake_minimum_required(VERSION 3.18)  # 3.18+ — родная поддержка языка CUDA
project(cuda_probe LANGUAGES CXX CUDA)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

# Архитектуру передаёт шаблон сборки: 87 для Orin, 75;86;89 для x86.
# Без явного значения CMake подставит архитектуру сборочной машины, что при
# кросс-компиляции даёт молча неверный результат.
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
  if(DEFINED ENV{CUDA_ARCH})
    set(CMAKE_CUDA_ARCHITECTURES $ENV{CUDA_ARCH})
  else()
    message(FATAL_ERROR
      "CMAKE_CUDA_ARCHITECTURES не задана. Передайте -DCMAKE_CUDA_ARCHITECTURES "
      "или установите переменную окружения CUDA_ARCH.")
  endif()
endif()
message(STATUS "cuda_probe: CMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHITECTURES}")

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
find_package(CUDAToolkit REQUIRED)

add_executable(cuda_probe_node
  src/cuda_probe_node.cpp
  src/vector_add.cu
)
target_include_directories(cuda_probe_node PRIVATE include)
target_link_libraries(cuda_probe_node CUDA::cudart)
ament_target_dependencies(cuda_probe_node rclcpp std_msgs)

set_target_properties(cuda_probe_node PROPERTIES
  CUDA_SEPARABLE_COMPILATION ON
)

install(TARGETS cuda_probe_node DESTINATION lib/${PROJECT_NAME})

ament_package()
