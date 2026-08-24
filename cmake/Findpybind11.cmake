# Minimal pybind11 finder for the FreeCAD OHOS build.
# FreeCAD's CAM and flat-mesh targets only consume the header include path;
# no pybind11 library is linked.  Keep the source tree relocatable through
# PYBIND11_ROOT instead of requiring a host package installation.

set(_pybind11_root "${PYBIND11_ROOT}")
if(NOT _pybind11_root)
    find_path(_pybind11_include
        NAMES pybind11/pybind11.h
        PATH_SUFFIXES include
    )
else()
    set(_pybind11_include "${_pybind11_root}/include")
endif()

if(EXISTS "${_pybind11_include}/pybind11/pybind11.h")
    set(pybind11_INCLUDE_DIR "${_pybind11_include}")
    set(pybind11_INCLUDE_DIRS "${_pybind11_include}")
    set(pybind11_VERSION "2.13.6")
    set(pybind11_FOUND TRUE)
else()
    set(pybind11_FOUND FALSE)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(pybind11
    REQUIRED_VARS pybind11_INCLUDE_DIR
    VERSION_VAR pybind11_VERSION
)

mark_as_advanced(pybind11_INCLUDE_DIR)
