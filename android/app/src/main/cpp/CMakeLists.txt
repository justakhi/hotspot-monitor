cmake_minimum_required(VERSION 3.22.1)
project(hotspot_probe C)

add_executable(hs_probe hs_probe.c quic_sni.c)
set_target_properties(hs_probe PROPERTIES
    OUTPUT_NAME "hs_probe"
    PREFIX "lib"
    SUFFIX ".so"
)
if(DEFINED CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set_target_properties(hs_probe PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}"
    )
endif()
target_compile_options(hs_probe PRIVATE -O2 -Wall -Wextra -fPIE)
target_link_options(hs_probe PRIVATE -pie)
