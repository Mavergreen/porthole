# The Mac half of caller identity: tools porthole-standin-bridge uses to name the Mac application
# behind a bridged connection and to stop its container stand-in when that application exits.
add_library(porthole_caller_walk STATIC caller_walk.c)
target_include_directories(porthole_caller_walk PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

add_executable(porthole-caller porthole-caller.c)
target_link_libraries(porthole-caller PRIVATE porthole_caller_walk)
mavericks_assert_binary_compatible(porthole-caller)

add_executable(test_caller_walk "${PROJECT_SOURCE_DIR}/tests/standin/test_caller_walk.c")
target_link_libraries(test_caller_walk PRIVATE porthole_caller_walk)
add_test(NAME caller_walk COMMAND test_caller_walk)

add_executable(porthole-watch-exit porthole-watch-exit.c)
target_link_libraries(porthole-watch-exit PRIVATE porthole_caller_walk)
mavericks_assert_binary_compatible(porthole-watch-exit)
