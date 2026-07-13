# Portable libretro host, built into the Android app and each desktop runner.
# The platform glue links libretro_host and provides the texture, input, and
# audio sinks through lh_callbacks.
cmake_minimum_required(VERSION 3.14)
project(libretro_host C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(libretro_host STATIC libretro_host.c)
target_include_directories(libretro_host PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Threads REQUIRED)
target_link_libraries(libretro_host PUBLIC Threads::Threads)
if(NOT WIN32)
  target_link_libraries(libretro_host PUBLIC ${CMAKE_DL_LIBS})
endif()

# Headless self-test: a stub core plus a harness that drives the host. Enable
# with -DLIBRETRO_HOST_TESTS=ON.
option(LIBRETRO_HOST_TESTS "Build the libretro host self-test" OFF)
if(LIBRETRO_HOST_TESTS)
  add_library(stub_core SHARED test/stub_core.c)
  set_target_properties(stub_core PROPERTIES PREFIX "" C_VISIBILITY_PRESET default)

  add_executable(libretro_host_test test/test_harness.c)
  target_link_libraries(libretro_host_test PRIVATE libretro_host)

  enable_testing()
  add_test(
    NAME libretro_host_test
    COMMAND libretro_host_test $<TARGET_FILE:stub_core> ${CMAKE_CURRENT_BINARY_DIR})
endif()
