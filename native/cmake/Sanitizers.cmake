function(apply_sanitizers target)
    if(ENABLE_ASAN)
        target_compile_options(${target} PRIVATE
            -fsanitize=address,undefined
            -fno-omit-frame-pointer -g3 -O1)
        target_link_options(${target} PRIVATE
            -fsanitize=address,undefined)
    endif()
    if(ENABLE_TSAN)
        target_compile_options(${target} PRIVATE
            -fsanitize=thread -g3 -O1)
        target_link_options(${target} PRIVATE -fsanitize=thread)
    endif()
endfunction()
