cmake_minimum_required(VERSION 3.18)
project(pulso_audio_engine VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization Flags
if (MSVC)
    add_compile_options(/O2 /Oi /fp:fast)
else()
    add_compile_options(-O3 -ffast-math -fvisibility=hidden)
endif()

# Enable ARM NEON on ARM64 platforms
if (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
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
if (ANDROID)
    find_library(log-lib log)
    find_library(aaudio-lib aaudio)
    target_link_libraries(pulso_core PRIVATE ${log-lib} ${aaudio-lib})
elseif (APPLE)
    find_library(AudioToolbox AudioToolbox)
    find_library(AVFoundation AVFoundation)
    target_link_libraries(pulso_core PRIVATE ${AudioToolbox} ${AVFoundation})
endif()
