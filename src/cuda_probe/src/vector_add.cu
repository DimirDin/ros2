// CUDA-часть пакета. Существование скомпилированного кода этого файла под
// целевую архитектуру и есть доказательство того, что кросс-компиляция CUDA
// действительно состоялась: scripts/verify-cuda.sh находит здешние ядра
// через cuobjdump в готовом бинаре.
#include "cuda_probe/vector_add.hpp"

#include <cuda_runtime.h>

#include <stdexcept>
#include <string>
#include <vector>

namespace cuda_probe
{
namespace
{

void check(cudaError_t err, const char * what)
{
  if (err != cudaSuccess) {
    throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(err));
  }
}

__global__ void vector_add_kernel(const float * a, const float * b, float * out, int n)
{
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    out[i] = a[i] + b[i];
  }
}

}  // namespace

std::vector<float> vector_add_on_gpu(
  const std::vector<float> & a,
  const std::vector<float> & b)
{
  if (a.size() != b.size()) {
    throw std::invalid_argument("vector_add_on_gpu: размеры векторов различаются");
  }

  const int n = static_cast<int>(a.size());
  const size_t bytes = a.size() * sizeof(float);

  float * d_a = nullptr;
  float * d_b = nullptr;
  float * d_out = nullptr;

  check(cudaMalloc(&d_a, bytes), "cudaMalloc(a)");
  check(cudaMalloc(&d_b, bytes), "cudaMalloc(b)");
  check(cudaMalloc(&d_out, bytes), "cudaMalloc(out)");

  check(cudaMemcpy(d_a, a.data(), bytes, cudaMemcpyHostToDevice), "cudaMemcpy(a)");
  check(cudaMemcpy(d_b, b.data(), bytes, cudaMemcpyHostToDevice), "cudaMemcpy(b)");

  constexpr int kThreads = 256;
  const int blocks = (n + kThreads - 1) / kThreads;
  vector_add_kernel<<<blocks, kThreads>>>(d_a, d_b, d_out, n);
  check(cudaGetLastError(), "запуск ядра");
  check(cudaDeviceSynchronize(), "cudaDeviceSynchronize");

  std::vector<float> out(a.size());
  check(cudaMemcpy(out.data(), d_out, bytes, cudaMemcpyDeviceToHost), "cudaMemcpy(out)");

  cudaFree(d_a);
  cudaFree(d_b);
  cudaFree(d_out);
  return out;
}

std::string describe_gpu()
{
  int count = 0;
  check(cudaGetDeviceCount(&count), "cudaGetDeviceCount");
  if (count == 0) {
    throw std::runtime_error("GPU не обнаружен");
  }

  cudaDeviceProp prop{};
  check(cudaGetDeviceProperties(&prop, 0), "cudaGetDeviceProperties");
  return std::string(prop.name) + " (sm_" + std::to_string(prop.major) +
         std::to_string(prop.minor) + ")";
}

}  // namespace cuda_probe
