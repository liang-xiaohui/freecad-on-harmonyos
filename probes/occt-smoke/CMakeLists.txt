cmake_minimum_required(VERSION 3.16)
project(freecad_ohos_occt_smoke LANGUAGES CXX)

find_package(OpenCASCADE CONFIG REQUIRED)

if(OpenCASCADE_MAJOR_VERSION GREATER 7 OR
   (OpenCASCADE_MAJOR_VERSION EQUAL 7 AND OpenCASCADE_MINOR_VERSION GREATER_EQUAL 8))
    set(OCCT_STEP_LIBRARIES TKDE TKDESTEP)
else()
    set(OCCT_STEP_LIBRARIES TKXSBase TKSTEPBase TKSTEPAttr TKSTEP)
endif()

add_executable(occt-smoke main.cpp)
target_compile_features(occt-smoke PRIVATE cxx_std_14)
target_include_directories(occt-smoke PRIVATE ${OpenCASCADE_INCLUDE_DIR})
target_link_libraries(occt-smoke PRIVATE
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
    ${OCCT_STEP_LIBRARIES}
)
