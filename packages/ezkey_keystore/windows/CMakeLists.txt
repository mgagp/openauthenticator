cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "ezkey_keystore")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "ezkey_keystore_plugin")

add_library(${PLUGIN_NAME} SHARED
  "ezkey_keystore_plugin.cpp"
  "include/ezkey_keystore/ezkey_keystore_plugin_c_api.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
# CNG: ncrypt (key storage providers), bcrypt (SHA-256), crypt32 (Base64).
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin ncrypt bcrypt crypt32)

set(ezkey_keystore_bundled_libraries "" PARENT_SCOPE)
