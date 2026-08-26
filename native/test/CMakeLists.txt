find_package(GTest REQUIRED)

add_executable(test_types test_types.cpp)
target_include_directories(test_types PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_types PRIVATE GTest::gtest_main)
apply_sanitizers(test_types)
if(ENABLE_COVERAGE)
    enable_coverage(test_types)
endif()
add_test(NAME test_types COMMAND test_types)

add_executable(test_remote_types test_remote_types.cpp)
target_include_directories(test_remote_types PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_remote_types PRIVATE GTest::gtest_main)
apply_sanitizers(test_remote_types)
if(ENABLE_COVERAGE)
    enable_coverage(test_remote_types)
endif()
add_test(NAME test_remote_types COMMAND test_remote_types)

add_executable(test_serial_queue test_serial_queue.cpp)
target_include_directories(test_serial_queue PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_serial_queue PRIVATE GTest::gtest_main pthread)
apply_sanitizers(test_serial_queue)
if(ENABLE_COVERAGE)
    enable_coverage(test_serial_queue)
endif()
add_test(NAME test_serial_queue COMMAND test_serial_queue)

add_executable(test_child_reaper test_child_reaper.cpp ${CMAKE_SOURCE_DIR}/src/child_reaper.cpp)
target_include_directories(test_child_reaper PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_child_reaper PRIVATE GTest::gtest_main pthread)
apply_sanitizers(test_child_reaper)
if(ENABLE_COVERAGE)
    enable_coverage(test_child_reaper)
endif()
add_test(NAME test_child_reaper COMMAND test_child_reaper)

add_executable(test_app_metadata test_app_metadata.cpp ${CMAKE_SOURCE_DIR}/src/app_metadata.cpp)
target_include_directories(test_app_metadata PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_app_metadata PRIVATE
    GTest::gtest_main
    PkgConfig::GLIB
)
apply_sanitizers(test_app_metadata)
if(ENABLE_COVERAGE)
    enable_coverage(test_app_metadata)
endif()
add_test(NAME test_app_metadata COMMAND test_app_metadata)

add_executable(test_installation_reader test_installation_reader.cpp)
target_include_directories(test_installation_reader PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_installation_reader PRIVATE
    GTest::gtest_main
    PkgConfig::FLATPAK
    flatpak_nc
)
apply_sanitizers(test_installation_reader)
if(ENABLE_COVERAGE)
    enable_coverage(test_installation_reader)
endif()
add_test(NAME test_installation_reader COMMAND test_installation_reader)

add_executable(test_transaction_bridge test_transaction_bridge.cpp)
target_include_directories(test_transaction_bridge PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_transaction_bridge PRIVATE
    GTest::gtest_main
    PkgConfig::FLATPAK
    pthread
)
apply_sanitizers(test_transaction_bridge)
if(ENABLE_COVERAGE)
    enable_coverage(test_transaction_bridge)
endif()
add_test(NAME test_transaction_bridge COMMAND test_transaction_bridge)
