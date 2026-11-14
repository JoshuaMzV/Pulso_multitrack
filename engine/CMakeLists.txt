cmake_minimum_required(VERSION 3.18)
project(pulso_audio_engine VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization Flags
if (MSVC)
    add_compile_options(/O2 /Oi /fp:fast)
else()
    add_compile_options(-O3 -fvisibility=hidden)
endif()

# Enable ARM NEON on ARM64 platforms
if (CMAKE_SYSTEM_PROCESSOR MATCHES "^armv7")
    if (NOT MSVC)
        add_compile_options(-mfpu=neon)
    endif()
endif()

# Include directories
include_directories(
    include
    src
)

set(SOURCES
    src/pulso_mixer_simd.cpp
    src/pulso_engine.cpp
)

add_library(pulso_core SHARED ${SOURCES})

target_include_directories(pulso_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Platform-specific link libraries
if (APPLE)
    find_library(AudioToolbox AudioToolbox)
    find_library(AVFoundation AVFoundation)
    target_link_libraries(pulso_core PRIVATE ${AudioToolbox} ${AVFoundation})
endif()
