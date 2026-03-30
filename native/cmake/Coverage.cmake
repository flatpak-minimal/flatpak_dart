function(enable_coverage target)
    find_program(LCOV    lcov    REQUIRED)
    find_program(GENHTML genhtml REQUIRED)
    target_compile_options(${target} PRIVATE --coverage -O0 -g3)
    target_link_options(${target} PRIVATE --coverage)
    add_custom_target(coverage
        COMMAND ${LCOV} --capture
                --directory ${CMAKE_BINARY_DIR}
                --output-file coverage.info
                --no-external
                --base-directory ${CMAKE_SOURCE_DIR}
                --exclude "*/generated/*"
                --exclude "*/dart_api_dl*"
                --ignore-errors unused
        COMMAND ${GENHTML} coverage.info
                --output-directory coverage_html
                --title "flatpak_dart C++ coverage" --legend
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating coverage report in coverage_html/")
endfunction()
