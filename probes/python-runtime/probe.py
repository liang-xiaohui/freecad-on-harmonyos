#!/usr/bin/env python3
import importlib
import json
import sys


REQUIRED_MODULES = [
    "_socket",
    "ctypes",
    "datetime",
    "hashlib",
    "http.server",
    "json",
    "threading",
    "urllib.parse",
    "xml.etree.ElementTree",
    "zipfile",
]


def check_binascii():
    import binascii

    payload = b"FreeCAD-on-HarmonyOS"
    assert binascii.unhexlify(binascii.hexlify(payload)) == payload


def check_ctypes():
    import ctypes

    strlen = ctypes.CDLL(None).strlen
    strlen.argtypes = [ctypes.c_char_p]
    strlen.restype = ctypes.c_size_t
    assert strlen(b"FreeCAD") == 7

    callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int)
    callback = callback_type(lambda value: value + 1)
    assert callback(41) == 42


def check_socketpair():
    import socket

    left, right = socket.socketpair()
    try:
        left.sendall(b"ohos")
        assert right.recv(4) == b"ohos"
    finally:
        left.close()
        right.close()


def check_zlib():
    import zlib

    payload = b"Part-Mesh-Import" * 64
    assert zlib.decompress(zlib.compress(payload)) == payload


FUNCTIONAL_CHECKS = {
    "binasciiRoundTrip": check_binascii,
    "ctypesCallAndCallback": check_ctypes,
    "socketPair": check_socketpair,
    "zlibRoundTrip": check_zlib,
}


def main():
    failures = {}
    for module_name in REQUIRED_MODULES:
        try:
            importlib.import_module(module_name)
        except Exception as exc:
            failures[module_name] = "%s: %s" % (type(exc).__name__, exc)

    functional_failures = {}
    for check_name, check in FUNCTIONAL_CHECKS.items():
        try:
            check()
        except Exception as exc:
            functional_failures[check_name] = "%s: %s" % (
                type(exc).__name__,
                exc,
            )

    result = {
        "executable": sys.executable,
        "version": sys.version,
        "requiredModules": REQUIRED_MODULES,
        "failures": failures,
        "functionalChecks": sorted(FUNCTIONAL_CHECKS),
        "functionalFailures": functional_failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if failures or functional_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
