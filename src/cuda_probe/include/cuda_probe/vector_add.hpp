#pragma once
#include <string>
#include <vector>

namespace cuda_probe
{

/// Складывает два вектора на GPU. Бросает std::runtime_error при ошибке CUDA.
std::vector<float> vector_add_on_gpu(
  const std::vector<float> & a,
  const std::vector<float> & b);

/// Название и compute capability первого доступного GPU, например "Orin (8.7)".
std::string describe_gpu();

}  // namespace cuda_probe
