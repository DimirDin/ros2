// ROS2-нода, выполняющая сложение векторов на GPU.
//
// Два режима:
//   --selftest — одиночная проверка без ROS-графа, код возврата 0/1.
//                Используется scripts/verify-cuda.sh на уровне 3.
//   без флага  — обычная нода, публикующая результат в /cuda_probe/status.
#include "cuda_probe/vector_add.hpp"

#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>

#include <chrono>
#include <cstring>
#include <iostream>
#include <memory>
#include <numeric>
#include <string>
#include <vector>

namespace
{

constexpr int kProbeSize = 1024;

/// Складывает [0..n) и [n..0) — каждый элемент результата должен равняться n-1.
/// Такая форма даёт независимую проверку каждого элемента, а не только суммы.
std::string run_probe()
{
  std::vector<float> a(kProbeSize);
  std::vector<float> b(kProbeSize);
  std::iota(a.begin(), a.end(), 0.0F);
  for (int i = 0; i < kProbeSize; ++i) {
    b[i] = static_cast<float>(kProbeSize - 1 - i);
  }

  const auto out = cuda_probe::vector_add_on_gpu(a, b);

  const float expected = static_cast<float>(kProbeSize - 1);
  for (size_t i = 0; i < out.size(); ++i) {
    if (out[i] != expected) {
      throw std::runtime_error(
              "неверный результат в позиции " + std::to_string(i) + ": " +
              std::to_string(out[i]) + " вместо " + std::to_string(expected));
    }
  }

  return cuda_probe::describe_gpu();
}

int selftest()
{
  try {
    std::cout << "cuda_probe: OK, GPU=" << run_probe() << std::endl;
    return 0;
  } catch (const std::exception & e) {
    std::cerr << "cuda_probe: ОШИБКА: " << e.what() << std::endl;
    return 1;
  }
}

class CudaProbeNode : public rclcpp::Node
{
public:
  CudaProbeNode()
  : Node("cuda_probe")
  {
    publisher_ = create_publisher<std_msgs::msg::String>("cuda_probe/status", 10);
    timer_ = create_wall_timer(
      std::chrono::seconds(1), [this]() {this->publish_status();});
  }

private:
  void publish_status()
  {
    std_msgs::msg::String msg;
    try {
      msg.data = "CUDA OK, GPU=" + run_probe();
    } catch (const std::exception & e) {
      msg.data = std::string("CUDA FAIL: ") + e.what();
      RCLCPP_ERROR(get_logger(), "%s", msg.data.c_str());
    }
    RCLCPP_INFO(get_logger(), "%s", msg.data.c_str());
    publisher_->publish(msg);
  }

  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
};

}  // namespace

int main(int argc, char ** argv)
{
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--selftest") == 0) {
      return selftest();
    }
  }

  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<CudaProbeNode>());
  rclcpp::shutdown();
  return 0;
}
