# LightGBM Static Library for ARM64 (with Headers)

[![Build and Push](https://github.com/jacobsvante/lightgbm-static-aarch64/actions/workflows/build.yml/badge.svg)](https://github.com/jacobsvante/lightgbm-static-aarch64/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/jacobsvante/lightgbm-static-aarch64)](https://hub.docker.com/r/jacobsvante/lightgbm-static-aarch64)
[![Docker Image Size](https://img.shields.io/docker/image-size/jacobsvante/lightgbm-static-aarch64/latest)](https://hub.docker.com/r/jacobsvante/lightgbm-static-aarch64)

Minimal Docker image containing the LightGBM static library (`lib_lightgbm.a`) and all necessary header files built for ARM64/aarch64 architecture with OpenMP support.

## 🚀 Quick Start

### Pull the image
```bash
docker pull jacobsvante/lightgbm-static-aarch64:latest
```

### Extract the library
```bash
# Extract library and headers to current directory
docker run --rm -v $(pwd):/output jacobsvante/lightgbm-static-aarch64:latest \
  sh -c "cp /lib/lib_lightgbm.a /output/ && cp -r /include /output/"
```

### Extract using Docker cp
```bash
# Create container
docker create --name lgbm jacobsvante/lightgbm-static-aarch64:latest

# Copy files
docker cp lgbm:/lib/lib_lightgbm.a ./
docker cp lgbm:/include ./

# Cleanup
docker rm lgbm
```

## 📦 Image Contents

The image contains:
- `/lib/lib_lightgbm.a` - The static library (~5-10 MB)
- `/include/LightGBM/` - All C API header files
  - `c_api.h` - Main C API interface
  - `export.h` - Export macros
  - `utils/*` - Utility headers
  - Additional internal headers
- `/build_info.txt` - Build configuration and header list

Base image: `busybox:1.36` (minimal ~1.5 MB base)
Total image size: ~10-15 MB

## 🏗️ Build Features

- **Architecture**: ARM64/aarch64
- **OpenMP**: Enabled (multi-threading support)
- **BLAS**: OpenBLAS
- **GPU**: Disabled
- **Static**: Fully static, no runtime dependencies
- **Compiler**: GCC with `-O3` optimization
- **Alpine**: Built on Alpine Linux 3.22

## 💻 Using the Library

### C++ Example
```cpp
// main.cpp
#include "LightGBM/c_api.h"
#include <vector>
#include <iostream>

int main() {
    // Your LightGBM code here
    std::cout << "LightGBM ready!" << std::endl;
    return 0;
}

// Compile with:
// g++ main.cpp -I./include -L. -l:lib_lightgbm.a -fopenmp -pthread -lm -o your_app
```

### CMake Example
```cmake
cmake_minimum_required(VERSION 3.10)
project(YourApp)

# Set include path for headers
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

find_package(OpenMP REQUIRED)
find_package(Threads REQUIRED)

add_executable(your_app main.cpp)
target_link_libraries(your_app
    ${CMAKE_CURRENT_SOURCE_DIR}/lib_lightgbm.a
    OpenMP::OpenMP_CXX
    Threads::Threads
    m
)
```

### Directory Structure After Extraction
```
your_project/
├── lib_lightgbm.a
├── include/
│   └── LightGBM/
│       ├── c_api.h         # Main API header
│       ├── export.h         # Export definitions
│       ├── utils/
│       │   ├── common.h
│       │   ├── log.h
│       │   └── ...
│       └── ...
├── build_info.txt
└── main.cpp                # Your application
```

## 🏷️ Available Tags

- `latest` - Latest stable build
- `stable` - Stable LightGBM version
- `v4.1.0`, `v4.0.0` - Specific LightGBM versions
- `main-YYYYMMDD` - Daily builds from main branch
- `sha-xxxxxxx` - Specific commit builds

## 🔧 GitHub Actions Setup

### 1. Fork this repository

### 2. Set up Docker Hub secrets
Go to Settings → Secrets and variables → Actions, add:
- `DOCKER_USERNAME` - Your Docker Hub username
- `DOCKER_TOKEN` - Docker Hub access token (not password)

### 3. Create Docker Hub access token
1. Log in to [Docker Hub](https://hub.docker.com)
2. Go to Account Settings → Security
3. Click "New Access Token"
4. Give it a descriptive name
5. Copy the token and add it as `DOCKER_TOKEN` secret

### 4. Update configuration
Edit `.github/workflows/build.yml`:
- Change `DOCKER_USERNAME` to your username
- Update `IMAGE_NAME` if desired
- Modify repository URLs in labels

### 5. Trigger a build
- Push to main branch
- Create a tag (`git tag v1.0.0 && git push --tags`)
- Manually trigger via Actions tab

## 📊 Verification

### Check library information
```bash
# View build info (includes header list)
docker run --rm jacobsvante/lightgbm-static-aarch64:latest cat /build_info.txt

# Check library size
docker run --rm jacobsvante/lightgbm-static-aarch64:latest ls -lh /lib/lib_lightgbm.a

# List all headers
docker run --rm jacobsvante/lightgbm-static-aarch64:latest find /include -type f -name "*.h"

# Count headers
docker run --rm jacobsvante/lightgbm-static-aarch64:latest sh -c "find /include -type f -name '*.h' | wc -l"

# View specific header
docker run --rm jacobsvante/lightgbm-static-aarch64:latest cat /include/LightGBM/c_api.h | head -50
```

### Verify on host
```bash
# After extraction
file lib_lightgbm.a
nm lib_lightgbm.a | grep LGBM_ | head -10

# Check headers are complete
ls -la include/LightGBM/
find include -name "*.h" | wc -l

# Verify you can compile against it
echo '#include "LightGBM/c_api.h"
int main() { return 0; }' > test.cpp
g++ test.cpp -I./include -L. -l:lib_lightgbm.a -pthread -lm -o test && echo "Headers OK!"
```

## 🔄 Multi-Architecture Builds

To build for both ARM64 and AMD64, uncomment the platform matrix in the workflow:

```yaml
strategy:
  matrix:
    platform:
      - linux/arm64
      - linux/amd64  # Uncomment this line
```

## 🐛 Troubleshooting

### QEMU Issues
If building ARM64 on AMD64 runners fails:
```yaml
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3
  with:
    platforms: arm64
    image: tonistiigi/binfmt:latest  # Add this for better compatibility
```

### Build Timeout
For large builds, increase the timeout:
```yaml
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    timeout-minutes: 120  # Increase from default 60
```

## 📄 License

This Docker image build process is MIT licensed. LightGBM itself is licensed under the [MIT License](https://github.com/microsoft/LightGBM/blob/master/LICENSE).

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📚 Resources

- [LightGBM Documentation](https://lightgbm.readthedocs.io/)
- [LightGBM C API](https://lightgbm.readthedocs.io/en/latest/C-API.html)
- [Docker Hub Repository](https://hub.docker.com/r/jacobsvante/lightgbm-static-aarch64)
- [GitHub Repository](https://github.com/jacobsvante/lightgbm-static-aarch64)
