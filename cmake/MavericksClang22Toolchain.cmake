# MavericksClang22Toolchain.cmake -- a CMake toolchain file: shipyard's MavericksToolchain.cmake (pinned SDK,
# arch, deployment target) plus the family compiler, clang22, at the release MAVERICKS_CLANG22_PIN/version
# names (MAVERICKS_CLANG22_PIN is a product's components/clang22 directory).
#
# mavergreen-conventions: "Products build with clang22 on every host, and nothing a build needs comes from
# the Command Line Tools." shipyard's fetch_clang22.sh gives this host's clang22: on 10.9 the installed native
# clang22 when it is the pinned release (else that release, fetched); on a modern Mac clang22-cross; on Linux
# the pinned archive. The compiler is chosen HERE, before project(), so compiler detection only ever runs it.
# Its driver config (clang.cfg) is used as shipped: it carries Recaulk, so a Recaulk fix reaches every build.
# Linking uses clang22's lld (no Command Line Tools ld64); archiving and Mach-O reading use its llvm-* tools.
#
# Nothing here is product-specific: it is written to move into shipyard unchanged.
#
#   shipyard-cmake -S . -B <dir> -DCMAKE_TOOLCHAIN_FILE=<this> -DMAVERICKS_CLANG22_PIN=<repo>/components/clang22

if(NOT MAVERICKS_CLANG22_PIN)
  message(FATAL_ERROR "MavericksClang22Toolchain.cmake: set MAVERICKS_CLANG22_PIN to the product's "
                      "components/clang22 directory (the pinned clang22 release)")
endif()
# try_compile and regeneration run from other directories: make the pin absolute (relative to where the
# configure was started) before anything uses it, and forward it to try_compile projects.
if(NOT IS_ABSOLUTE "${MAVERICKS_CLANG22_PIN}")
  get_filename_component(MAVERICKS_CLANG22_PIN "${MAVERICKS_CLANG22_PIN}" ABSOLUTE BASE_DIR "$ENV{PWD}")
  set(MAVERICKS_CLANG22_PIN "${MAVERICKS_CLANG22_PIN}" CACHE PATH "the product's components/clang22 directory" FORCE)
endif()
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES MAVERICKS_CLANG22_PIN)

if(DEFINED ENV{SHIPYARD_SCRIPTS} AND EXISTS "$ENV{SHIPYARD_SCRIPTS}/fetch_clang22.sh")
  get_filename_component(_mc22_shipyard "$ENV{SHIPYARD_SCRIPTS}/.." ABSOLUTE)
else()
  set(_mc22_shipyard "/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard")
endif()
# The compiler is named BEFORE shipyard's toolchain is included: shipyard leaves a named compiler alone,
# and otherwise picks its own pinned clang22, which may not be this product's pin.
execute_process(COMMAND sh "${_mc22_shipyard}/scripts/fetch_clang22.sh" "${MAVERICKS_CLANG22_PIN}"
  OUTPUT_VARIABLE _mc22_root OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_VARIABLE _mc22_err RESULT_VARIABLE _mc22_rc)
if(NOT _mc22_rc EQUAL 0 OR NOT EXISTS "${_mc22_root}/bin/clang")
  message(FATAL_ERROR "MavericksClang22Toolchain.cmake: no pinned clang22 -- fetch_clang22.sh "
                      "${MAVERICKS_CLANG22_PIN} exited ${_mc22_rc} with '${_mc22_root}' and said: ${_mc22_err}")
endif()
file(READ "${MAVERICKS_CLANG22_PIN}/version" _mc22_ver)
string(STRIP "${_mc22_ver}" _mc22_ver)

foreach(_mc22_lang C OBJC)
  if(CMAKE_${_mc22_lang}_COMPILER AND NOT CMAKE_${_mc22_lang}_COMPILER STREQUAL "${_mc22_root}/bin/clang")
    message(FATAL_ERROR "CMAKE_${_mc22_lang}_COMPILER is ${CMAKE_${_mc22_lang}_COMPILER}, but this build compiles "
      "only with the pinned clang22 ${_mc22_ver} (${_mc22_root}/bin/clang): remove the override (or the build "
      "directory) and configure again.")
  endif()
  set(CMAKE_${_mc22_lang}_COMPILER "${_mc22_root}/bin/clang")
endforeach()
foreach(_mc22_lang CXX OBJCXX)
  if(NOT CMAKE_${_mc22_lang}_COMPILER)
    set(CMAKE_${_mc22_lang}_COMPILER "${_mc22_root}/bin/clang++")
  endif()
endforeach()
include("${_mc22_shipyard}/MavericksToolchain.cmake")

foreach(_mc22_pair AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip
                   INSTALL_NAME_TOOL=llvm-install-name-tool OTOOL=llvm-otool LIPO=llvm-lipo)
  string(REPLACE "=" ";" _mc22_pair "${_mc22_pair}")
  list(GET _mc22_pair 0 _mc22_var)
  list(GET _mc22_pair 1 _mc22_tool)
  if(EXISTS "${_mc22_root}/bin/${_mc22_tool}")
    set(CMAKE_${_mc22_var} "${_mc22_root}/bin/${_mc22_tool}" CACHE FILEPATH "clang22's ${_mc22_tool}" FORCE)
  endif()
endforeach()
foreach(_mc22_kind EXE SHARED MODULE)
  set(CMAKE_${_mc22_kind}_LINKER_FLAGS_INIT "-fuse-ld=lld")
endforeach()
set(MAVERICKS_CLANG22_ROOT "${_mc22_root}" CACHE PATH "the pinned clang22 this build compiles with" FORCE)
set(MAVERICKS_CLANG22_VERSION "${_mc22_ver}" CACHE STRING "the pinned clang22 release" FORCE)
