function(bare_platform result)
  set(platform ${CMAKE_SYSTEM_NAME})

  if(NOT platform)
    set(platform ${CMAKE_HOST_SYSTEM_NAME})
  endif()

  string(TOLOWER ${platform} platform)

  if(platform MATCHES "darwin|ios|linux|android")
    set(${result} ${platform})
  elseif(platform MATCHES "windows")
    set(${result} "win32")
  else()
    set(${result} "unknown")
  endif()

  return(PROPAGATE ${result})
endfunction()

function(bare_arch result)
  if(APPLE AND CMAKE_OSX_ARCHITECTURES)
    set(arch ${CMAKE_OSX_ARCHITECTURES})
  elseif(MSVC AND CMAKE_GENERATOR_PLATFORM)
    set(arch ${CMAKE_GENERATOR_PLATFORM})
  else()
    set(arch ${CMAKE_SYSTEM_PROCESSOR})
  endif()

  if(NOT arch)
    set(arch ${CMAKE_HOST_SYSTEM_PROCESSOR})
  endif()

  string(TOLOWER ${arch} arch)

  if(arch MATCHES "arm64|aarch64")
    set(${result} "arm64")
  elseif(arch MATCHES "armv7-a")
    set(${result} "arm")
  elseif(arch MATCHES "x64|x86_64|amd64")
    set(${result} "x64")
  elseif(arch MATCHES "x86|i386|i486|i586|i686")
    set(${result} "ia32")
  else()
    set(${result} "unknown")
  endif()

  return(PROPAGATE ${result})
endfunction()

function(bare_simulator result)
  set(sysroot ${CMAKE_OSX_SYSROOT})

  if(sysroot MATCHES "iPhoneSimulator")
    set(${result} YES)
  else()
    set(${result} NO)
  endif()

  return(PROPAGATE ${result})
endfunction()

function(bare_target result)
  bare_platform(platform)
  bare_arch(arch)
  bare_simulator(simulator)

  set(target ${platform}-${arch})

  if(simulator)
    set(target ${target}-simulator)
  endif()

  set(${result} ${target})

  return(PROPAGATE ${result})
endfunction()

function(add_bare_module target)
  bare_include_directories(includes)

  add_library(${target} OBJECT)

  set_target_properties(
    ${target}
    PROPERTIES
    C_STANDARD 11
    CXX_STANDARD 20
    POSITION_INDEPENDENT_CODE ON
  )

  target_include_directories(
    ${target}
    PRIVATE
      ${includes}
  )

  find_bare(bare)

  add_executable(${target}_import_lib IMPORTED)

  set_target_properties(
    ${target}_import_lib
    PROPERTIES
    ENABLE_EXPORTS ON
    IMPORTED_LOCATION ${bare}
  )

  if(MSVC)
    cmake_path(GET bare PARENT_PATH root)
    cmake_path(GET root PARENT_PATH root)

    find_library(
      bare_lib
      NAMES bare
      HINTS ${root}/lib
    )

    set_target_properties(
      ${target}_import_lib
      PROPERTIES
      IMPORTED_IMPLIB ${bare_lib}
    )
  endif()

  add_library(${target}_module MODULE $<TARGET_OBJECTS:${target}>)

  set_target_properties(
    ${target}_module
    PROPERTIES
    OUTPUT_NAME addon
    PREFIX ""
    SUFFIX ".bare"

    # Automatically export all available symbols on Windows. Without this,
    # module authors would have to explicitly export public symbols.
    WINDOWS_EXPORT_ALL_SYMBOLS ON
  )

  target_link_libraries(
    ${target}_module
    PRIVATE
      ${target}_import_lib
    PUBLIC
      $<TARGET_PROPERTY:${target},INTERFACE_LINK_LIBRARIES>
  )
endfunction()

function(include_bare_module target path)
  if(NOT TARGET ${target})
    bare_module_directory(root)

    add_subdirectory(
      ${root}/${path}
      ${path}
      EXCLUDE_FROM_ALL
    )

    set(filename "/${path}")

    cmake_path(NATIVE_PATH filename NORMALIZE filename)

    string(REPLACE "\\" "\\\\" filename ${filename})

    target_compile_definitions(
      ${target}
      PUBLIC
        BARE_MODULE_FILENAME="${filename}"
        BARE_MODULE_REGISTER_CONSTRUCTOR
        NAPI_MODULE_FILENAME="${filename}"
        NAPI_MODULE_REGISTER_CONSTRUCTOR
    )
  endif()
endfunction()

function(link_bare_module receiver target path)
  include_bare_module(${target} ${path})

  target_sources(
    ${receiver}
    PUBLIC
      $<TARGET_OBJECTS:${target}>
  )

  target_link_libraries(
    ${receiver}
    PUBLIC
      $<TARGET_PROPERTY:${target},INTERFACE_LINK_LIBRARIES>
  )
endfunction()

function(bare_include_directories result)
  find_bare_dev(bare_dev)

  execute_process(
    COMMAND ${bare_dev} paths include
    OUTPUT_VARIABLE bare
  )

  list(APPEND ${result} ${bare})

  return(PROPAGATE ${result})
endfunction()

function(bare_module_directory result)
  set(dirname ${CMAKE_CURRENT_LIST_DIR})

  cmake_path(GET dirname ROOT_PATH root)

  while(TRUE)
    cmake_path(
      APPEND dirname node_modules
      OUTPUT_VARIABLE target
    )

    if(IS_DIRECTORY ${target})
      set(${result} ${dirname})

      cmake_path(NATIVE_PATH ${result} NORMALIZE ${result})

      return(PROPAGATE ${result})
    endif()

    if(dirname PATH_EQUAL root)
      break()
    endif()

    cmake_path(GET dirname PARENT_PATH dirname)
  endwhile()

  set(${result} NOTFOUND)

  return(PROPAGATE ${result})
endfunction()

function(add_bare_bundle)
  cmake_parse_arguments(
    PARSE_ARGV 0 ARGV "" "CWD;ENTRY;OUT;TARGET;IMPORT_MAP;NODE_MODULES;CONFIG" "DEPENDS"
  )

  if(ARGV_CWD)
    cmake_path(ABSOLUTE_PATH ARGV_CWD BASE_DIRECTORY ${CMAKE_CURRENT_LIST_DIR})
  else()
    set(ARGV_CWD ${CMAKE_CURRENT_LIST_DIR})
  endif()

  list(APPEND args --cwd ${ARGV_CWD})

  if(ARGV_CONFIG)
    cmake_path(ABSOLUTE_PATH ARGV_CONFIG BASE_DIRECTORY ${ARGV_CWD})

    list(APPEND args --config ${ARGV_CONFIG})

    list(APPEND ARGV_DEPENDS ${ARGV_CONFIG})
  endif()

  if(ARGV_IMPORT_MAP)
    cmake_path(ABSOLUTE_PATH ARGV_IMPORT_MAP BASE_DIRECTORY ${ARGV_CWD})

    list(APPEND args --import-map ${ARGV_IMPORT_MAP})

    list(APPEND ARGV_DEPENDS ${ARGV_IMPORT_MAP})
  endif()

  if(ARGV_NODE_MODULES)
    cmake_path(ABSOLUTE_PATH ARGV_NODE_MODULES BASE_DIRECTORY ${ARGV_CWD})

    list(APPEND args --node-modules ${ARGV_NODE_MODULES})
  else()
    bare_module_directory(root)

    list(APPEND args --node-modules ${root}/node_modules)
  endif()

  list(APPEND args_bundle ${args})

  list(APPEND args_dependencies ${args})

  if(ARGV_TARGET)
    list(APPEND args_bundle --target ${ARGV_TARGET})
  endif()

  cmake_path(ABSOLUTE_PATH ARGV_OUT BASE_DIRECTORY ${ARGV_CWD})

  list(APPEND args_bundle --out ${ARGV_OUT})

  list(APPEND args_dependencies --out ${ARGV_OUT}.d)

  cmake_path(ABSOLUTE_PATH ARGV_ENTRY BASE_DIRECTORY ${ARGV_CWD})

  list(APPEND ARGV_DEPENDS ${ARGV_ENTRY})

  list(APPEND args_bundle ${ARGV_ENTRY})

  list(APPEND args_dependencies ${ARGV_ENTRY})

  find_bare_dev(bare_dev)

  list(REMOVE_DUPLICATES ARGV_DEPENDS)

  add_custom_command(
    COMMAND ${bare_dev} dependencies ${args_dependencies}
    WORKING_DIRECTORY ${ARGV_CWD}
    OUTPUT ${ARGV_OUT}.d
    DEPENDS ${ARGV_DEPENDS}
    VERBATIM
  )

  add_custom_command(
    COMMAND ${bare_dev} bundle ${args_bundle}
    WORKING_DIRECTORY ${ARGV_CWD}
    OUTPUT ${ARGV_OUT}
    DEPENDS ${ARGV_OUT}.d
    DEPFILE ${ARGV_OUT}.d
    VERBATIM
  )
endfunction()

function(mirror_drive)
  cmake_parse_arguments(
    PARSE_ARGV 0 ARGV "" "CWD;SOURCE;DESTINATION;PREFIX;CHECKOUT" ""
  )

  if(ARGV_CWD)
    list(APPEND args --cwd ${ARGV_CWD})
  endif()

  if(ARGV_PREFIX)
    list(APPEND args --prefix ${ARGV_PREFIX})
  endif()

  if(ARGV_CHECKOUT)
    list(APPEND args --checkout ${ARGV_CHECKOUT})
  endif()

  list(APPEND args ${ARGV_SOURCE} ${ARGV_DESTINATION})

  if(ARGV_CWD)
    cmake_path(ABSOLUTE_PATH ARGV_CWD BASE_DIRECTORY ${CMAKE_CURRENT_LIST_DIR})
  else()
    set(ARGV_CWD ${CMAKE_CURRENT_LIST_DIR})
  endif()

  find_bare_dev(bare_dev)

  message(STATUS "Mirroring drive ${ARGV_SOURCE} into ${ARGV_DESTINATION}")

  execute_process(
    COMMAND ${bare_dev} drive mirror ${args}
    WORKING_DIRECTORY ${ARGV_CWD}
  )
endfunction()

function(find_bare result)
  if(WIN32)
    find_program(
      bare_bin
      NAMES bare.cmd bare
      REQUIRED
    )
  else()
    find_program(
      bare_bin
      NAMES bare
      REQUIRED
    )
  endif()

  execute_process(
    COMMAND ${bare_bin} -p "Bare.argv[0]"
    OUTPUT_VARIABLE bare
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
  )

  set(${result} ${bare})

  return(PROPAGATE ${result})
endfunction()

function(find_bare_dev result)
  bare_module_directory(root)

  if(WIN32)
    find_program(
      bare_dev
      NAMES bare-dev.cmd bare-dev
      HINTS ${root}/node_modules/.bin
      REQUIRED
    )
  else()
    find_program(
      bare_dev
      NAMES bare-dev
      HINTS ${root}/node_modules/.bin
      REQUIRED
    )
  endif()

  set(${result} ${bare_dev})

  return(PROPAGATE ${result})
endfunction()

function(add_bare_dependencies)
  find_bare_dev(bare_dev)

  execute_process(
    COMMAND ${bare_dev} paths include
    OUTPUT_VARIABLE bare
  )

  if(NOT TARGET bare)
    add_library(bare INTERFACE IMPORTED)

    target_include_directories(
      bare
      INTERFACE
        ${bare}
    )
  endif()

  if(NOT TARGET uv)
    add_library(uv INTERFACE IMPORTED)

    target_include_directories(
      uv
      INTERFACE
        ${bare}
    )
  endif()

  if(NOT TARGET js)
    add_library(js INTERFACE IMPORTED)

    target_include_directories(
      js
      INTERFACE
        ${bare}
    )
  endif()

  if(NOT TARGET utf)
    add_library(utf INTERFACE IMPORTED)

    target_include_directories(
      utf
      INTERFACE
        ${bare}
    )
  endif()
endfunction()