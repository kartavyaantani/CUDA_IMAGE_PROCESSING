cmake_minimum_required(VERSION 3.10)
project(gpu_img_proc)

# Enable verbose CMake output (optional)
set(CMAKE_VERBOSE_MAKEFILE ON)

# Find required packages
find_package(CUDA REQUIRED)
find_package(OpenCV REQUIRED)

# Include OpenCV headers
include_directories(${OpenCV_INCLUDE_DIRS})

# Ensure the correct compute capability for RTX 3050 (sm_86)
# Also fix nvcc flag format (avoid semicolon here)
set(CUDA_NVCC_FLAGS "${CUDA_NVCC_FLAGS} -arch=sm_86 -std=c++11 -O2 -DVERBOSE")

# Add preprocessor definition to enable M_PI
add_definitions(-D_USE_MATH_DEFINES)

# CUDA executable with multiple source files
cuda_add_executable(main main.cu kernel.cu kernelcall.cu)

# Link OpenCV libraries
target_link_libraries(main ${OpenCV_LIBS})
