cmake_minimum_required(VERSION 3.13)

if(NOT DEFINED ENV{PICO_SDK_PATH})
    message(FATAL_ERROR "PICO_SDK_PATH is required. Run scripts/build-firmware.sh.")
endif()

include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(deskagent_firmware C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(deskagent_firmware
    src/main.c
)

pico_generate_pio_header(
    deskagent_firmware
    ${CMAKE_CURRENT_LIST_DIR}/src/ws2812.pio
)

target_link_libraries(deskagent_firmware
    pico_stdlib
    pico_unique_id
    hardware_pio
)

target_compile_definitions(deskagent_firmware PRIVATE
    PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS=0
)

pico_enable_stdio_usb(deskagent_firmware 1)
pico_enable_stdio_uart(deskagent_firmware 0)
pico_add_extra_outputs(deskagent_firmware)
