# Coverage instrumentation and reporting.
#
# enable_coverage() must be applied to every target whose execution should be
# measured, tests included. Three of the four test suites exercise header-only
# code (flatpak_types.h, glaze_meta.h, flatpak_post.h) and never link
# flatpak_nc, so instrumenting only the library left them invisible: the codec
# sat at 91% while the report claimed the project was near zero.
#
# Reporting goes through gcovr rather than lcov. lcov 2.0 cannot parse the gcov
# format emitted by recent gcc (16.x reports rates above 100% and 0% functions),
# and it is the version shipped by current distributions. gcovr handles both old
# and new gcov, and still writes an lcov info file for the CI reporter.
#
# add_coverage_report() creates the `coverage` target. Call it once, after all
# instrumented targets are defined.

function(enable_coverage target)
    target_compile_options(${target} PRIVATE --coverage -O0 -g3)
    target_link_options(${target} PRIVATE --coverage)
endfunction()

function(add_coverage_report)
    find_program(GCOVR gcovr REQUIRED)

    set(GCOVR_FILTERS
        --exclude ".*/test/.*"
        --exclude ".*dart_api.*"
        --exclude ".*/generated/.*"
        --exclude ".*/_deps/.*")

    add_custom_target(coverage
        COMMAND ${CMAKE_COMMAND} -E make_directory coverage_html
        COMMAND ${CMAKE_CTEST_COMMAND} --test-dir ${CMAKE_BINARY_DIR}/test
                --output-on-failure
        COMMAND ${GCOVR}
                --root ${CMAKE_SOURCE_DIR}
                --object-directory ${CMAKE_BINARY_DIR}
                ${GCOVR_FILTERS}
                --lcov coverage.info
                --html-details coverage_html/index.html
                --txt
                --print-summary
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating coverage report in coverage_html/")
endfunction()
