#include <string>
#include <vector>
#include <stdexcept>
int main() {
  try {
    std::vector<std::string> v;
    v.push_back("hello-libcxx");
    throw std::runtime_error(v[0]);
  } catch (const std::exception &e) {
    return (int)std::string(e.what()).size();
  }
  return -1;
}
