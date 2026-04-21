cmake_minimum_required(VERSION 3.22)
project(sparks_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Vulkan REQUIRED)

add_library(sparks_native SHARED
    sparks_jni.cpp
    vulkan_engine.cpp
    vulkan_utils.cpp
    benchmark_engine.cpp
)

target_include_directories(sparks_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(sparks_native
    android
    log
    Vulkan::Vulkan
)
