#!/usr/bin/env python3
"""Build the CPython extensions disabled by the OpenHarmony SDK package."""

import argparse
import os
from pathlib import Path

from distutils.core import Extension, setup
from distutils import sysconfig as distutils_sysconfig


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--python-prefix", required=True, type=Path)
    parser.add_argument("--libffi-prefix", required=True, type=Path)
    parser.add_argument("--openssl-prefix", required=True, type=Path)
    parser.add_argument("--build-temp", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    source = args.source.resolve()
    python_prefix = args.python_prefix.resolve()
    libffi_prefix = args.libffi_prefix.resolve()
    openssl_prefix = args.openssl_prefix.resolve()
    build_temp = args.build_temp.resolve()
    output_dir = args.output_dir.resolve()
    modules = source / "Modules"

    python_include = python_prefix / "include" / "python3.11"
    common_include_dirs = [
        str(python_include),
        str(source / "Include"),
        str(source / "Include" / "internal"),
        str(modules),
    ]
    python_library_dirs = [str(python_prefix / "lib")]
    common_libraries = ["python3.11"]

    extensions = [
        Extension(
            "_socket",
            sources=[str(modules / "socketmodule.c")],
            include_dirs=common_include_dirs,
            library_dirs=python_library_dirs,
            libraries=common_libraries,
        ),
        Extension(
            "binascii",
            sources=[str(modules / "binascii.c")],
            include_dirs=common_include_dirs,
            library_dirs=python_library_dirs,
            libraries=common_libraries + ["z"],
            define_macros=[("USE_ZLIB_CRC32", "1")],
        ),
        Extension(
            "zlib",
            sources=[str(modules / "zlibmodule.c")],
            include_dirs=common_include_dirs,
            library_dirs=python_library_dirs,
            libraries=common_libraries + ["z"],
            define_macros=[("Py_BUILD_CORE_MODULE", "1")],
        ),
        Extension(
            "_ctypes",
            sources=[
                str(modules / "_ctypes" / "_ctypes.c"),
                str(modules / "_ctypes" / "callbacks.c"),
                str(modules / "_ctypes" / "callproc.c"),
                str(modules / "_ctypes" / "stgdict.c"),
                str(modules / "_ctypes" / "cfield.c"),
            ],
            include_dirs=common_include_dirs
            + [
                str(modules / "_ctypes"),
                str(libffi_prefix / "include"),
            ],
            library_dirs=python_library_dirs + [str(libffi_prefix / "lib")],
            libraries=common_libraries + ["ffi", "dl"],
            define_macros=[
                ("HAVE_FFI_PREP_CIF_VAR", "1"),
                ("HAVE_FFI_PREP_CLOSURE_LOC", "1"),
                ("HAVE_FFI_CLOSURE_ALLOC", "1"),
            ],
        ),
        # The SDK runtime ships no _ssl, so urllib/requests can only speak
        # plain HTTP. The AI workbench talks to LLM APIs over TLS, so the
        # module is rebuilt here against the CPPLib OpenSSL build for OHOS.
        Extension(
            "_ssl",
            sources=[str(modules / "_ssl.c")],
            include_dirs=common_include_dirs + [str(openssl_prefix / "include")],
            library_dirs=python_library_dirs + [str(openssl_prefix / "lib")],
            libraries=common_libraries + ["ssl", "crypto"],
        ),
    ]

    output_dir.mkdir(parents=True, exist_ok=True)
    build_temp.mkdir(parents=True, exist_ok=True)
    os.chdir(modules)

    # The SDK sysconfig contains paths from its original /srv/workspace build.
    # Environment CFLAGS are appended by distutils, so clear the stale base first.
    config_vars = distutils_sysconfig.get_config_vars()
    config_vars["CFLAGS"] = ""
    config_vars["CCSHARED"] = "-fPIC"
    config_vars["CPPFLAGS"] = ""
    config_vars["INCLUDEPY"] = str(python_include)
    config_vars["LIBDIR"] = str(python_prefix / "lib")

    setup(
        name="openharmony-cpython-missing-extensions",
        version="3.11.4",
        ext_modules=extensions,
        script_args=[
            "build_ext",
            "--force",
            "--build-temp",
            str(build_temp),
            "--build-lib",
            str(output_dir),
        ],
    )


if __name__ == "__main__":
    main()
