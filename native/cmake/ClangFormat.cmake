function(add_clang_format_targets)
    find_program(CLANG_FORMAT_EXE NAMES clang-format-19 clang-format REQUIRED)
    file(GLOB_RECURSE ALL_SOURCES
        ${CMAKE_SOURCE_DIR}/src/*.cpp
        ${CMAKE_SOURCE_DIR}/include/*.h
        ${CMAKE_SOURCE_DIR}/test/*.cpp)
    list(FILTER ALL_SOURCES EXCLUDE REGEX ".*/generated/.*")
    list(FILTER ALL_SOURCES EXCLUDE REGEX ".*/dart_api_dl.*")

    add_custom_target(format-check
        COMMAND ${CLANG_FORMAT_EXE} --dry-run --Werror ${ALL_SOURCES}
        COMMENT "Checking format with clang-format-19")
    add_custom_target(format-fix
        COMMAND ${CLANG_FORMAT_EXE} -i ${ALL_SOURCES}
        COMMENT "Auto-formatting with clang-format-19")
endfunction()
