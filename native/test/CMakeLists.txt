find_package(GTest REQUIRED)

add_executable(test_types test_types.cpp)
target_include_directories(test_types PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_types PRIVATE GTest::gtest_main)
add_test(NAME test_types COMMAND test_types)

add_executable(test_remote_types test_remote_types.cpp)
target_include_directories(test_remote_types PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_remote_types PRIVATE GTest::gtest_main)
add_test(NAME test_remote_types COMMAND test_remote_types)

add_executable(test_installation_reader test_installation_reader.cpp)
target_include_directories(test_installation_reader PRIVATE ${CMAKE_SOURCE_DIR}/include)
target_link_libraries(test_installation_reader PRIVATE
    GTest::gtest_main
    PkgConfig::FLATPAK
)
add_test(NAME test_installation_reader COMMAND test_installation_reader)
