function(apply_clang_tidy target)
    if(ENABLE_CLANG_TIDY)
        find_program(CLANG_TIDY_EXE NAMES clang-tidy-19 clang-tidy REQUIRED)
        set(CHECKS
            "-*,bugprone-*,cppcoreguidelines-*,modernize-*,"
            "performance-*,readability-*,"
            "-modernize-use-trailing-return-type,"
            "-cppcoreguidelines-avoid-magic-numbers,"
            "-readability-magic-numbers")
        list(JOIN CHECKS "" CHECKS_STR)
        set_target_properties(${target} PROPERTIES
            CXX_CLANG_TIDY
            "${CLANG_TIDY_EXE};-checks=${CHECKS_STR};--warnings-as-errors=*")
    endif()
endfunction()
