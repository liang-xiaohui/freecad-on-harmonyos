cmake_minimum_required(VERSION 3.16)
project(freecad_headless_acceptance LANGUAGES CXX)

set(CPP_LIB_ROOT "/storage/Users/currentUser/CPPLib" CACHE PATH "CPPLib root")
set(PYTHON_ROOT "${CPP_LIB_ROOT}/install/python/3.11.4/ohos/arm64-v8a" CACHE PATH "OHOS Python prefix")
set(OCCT_ROOT "${CPP_LIB_ROOT}/install/occt/7.8.1/ohos/arm64-v8a" CACHE PATH "OHOS OpenCASCADE prefix")

add_library(freecadacceptance SHARED acceptance.cpp)
target_compile_features(freecadacceptance PRIVATE cxx_std_17)
set_target_properties(freecadacceptance PROPERTIES
  SKIP_BUILD_RPATH TRUE
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/native-output"
)
target_include_directories(freecadacceptance PRIVATE
  "${PYTHON_ROOT}/include/python3.11"
  "${OCCT_ROOT}/include/opencascade"
)

set(OCCT_CORE_LIBRARIES
  TKernel
  TKMath
  TKG2d
  TKG3d
  TKBRep
  TKGeomBase
  TKGeomAlgo
  TKTopAlgo
  TKPrim
  TKBO
  TKBool
)

if(EXISTS "${OCCT_ROOT}/lib/libTKDESTEP.so")
  set(OCCT_STEP_LIBRARIES TKDE TKXSBase TKDESTEP)
else()
  set(OCCT_STEP_LIBRARIES TKXSBase TKSTEPBase TKSTEPAttr TKSTEP)
endif()

foreach(OCCT_LIBRARY IN LISTS OCCT_CORE_LIBRARIES OCCT_STEP_LIBRARIES)
  target_link_libraries(freecadacceptance PRIVATE "${OCCT_ROOT}/lib/lib${OCCT_LIBRARY}.so")
endforeach()

target_link_libraries(freecadacceptance PRIVATE
  "${PYTHON_ROOT}/lib/libpython3.11.so"
  libace_napi.z.so
  libhilog_ndk.z.so
  librawfile.z.so
  libdl.so
  z
)
target_link_options(freecadacceptance PRIVATE "-Wl,-rpath,\$ORIGIN")
