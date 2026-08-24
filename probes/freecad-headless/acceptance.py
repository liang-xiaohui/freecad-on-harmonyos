import json
import math
import os
import pathlib
import sys
import traceback
import zipfile


OUTPUT_DIR = pathlib.Path(os.environ["FREECAD_PROBE_OUTPUT_DIR"])
RESULT_PATH = OUTPUT_DIR / "freecad-acceptance.json"
TESTS = []
STATE = {}


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def prepare_freecad_layout():
    """Build the directory layout expected by FreeCAD from the HAP payload."""
    root = pathlib.Path(os.environ["FREECAD_PROBE_ROOT"])
    runtime_zip = OUTPUT_DIR / "runtime" / "freecad-runtime.zip"
    home = OUTPUT_DIR / "freecad-home"
    home.mkdir(parents=True, exist_ok=True)

    if not (home / "Mod").is_dir() or not (home / "Ext").is_dir():
        with zipfile.ZipFile(runtime_zip) as archive:
            archive.extractall(home)

    for module in (
        "FreeCAD.so",
        "Import.so",
        "Materials.so",
        "Mesh.so",
        "Part.so",
        "Sketcher.so",
        "_PartDesign.so",
    ):
        check((root / module).is_file(), f"missing native FreeCAD module: {module}")

    loader_path = os.environ.get("LD_LIBRARY_PATH", "")
    os.environ["LD_LIBRARY_PATH"] = os.pathsep.join(
        path for path in (str(root), loader_path) if path
    )
    # FreeCAD's application home must contain its Mod/ tree（python 模块目录），
    # 指向解压后的 freecad-home；native .so 模块根经 FREECAD_APP_LIBRARY_DIR 指定。
    os.environ["FREECAD_APP_HOME"] = str(home)
    os.environ["FREECAD_APP_LIBRARY_DIR"] = str(root)
    os.environ["FREECAD_APP_RESOURCE_DIR"] = str(home / "share")
    sys.path.insert(0, str(root))
    sys.path.insert(1, str(home / "Ext"))

def run_test(name, operation):
    try:
        details = operation() or {}
        TESTS.append({"name": name, "ok": True, "details": details})
    except Exception as error:
        TESTS.append(
            {
                "name": name,
                "ok": False,
                "error": f"{type(error).__name__}: {error}",
                "traceback": traceback.format_exc(),
            }
        )


def test_occt_cpp():
    step_path = OUTPUT_DIR / "occt-smoke.step"
    volume = float(os.environ["FREECAD_OCCT_SMOKE_VOLUME"])
    check(math.isfinite(volume) and volume > 0.0, "invalid direct OCCT volume")
    check(step_path.stat().st_size > 0, "direct OCCT STEP output is empty")
    return {"volume": volume, "stepBytes": step_path.stat().st_size}


def test_imports():
    import FreeCAD as App
    import Import
    import Materials
    import Mesh
    import Part
    import PartDesign
    import Sketcher

    STATE.update(App=App, Import=Import, Mesh=Mesh, Part=Part)
    version = ".".join(App.Version()[:3])
    check(version == "1.1.2", f"unexpected FreeCAD version: {version}")
    return {
        "freecadVersion": version,
        "modules": [
            "FreeCAD",
            "Part",
            "Mesh",
            "Import",
            "Materials",
            "Sketcher",
            "PartDesign",
        ],
    }


def test_geometry():
    App = STATE["App"]
    Part = STATE["Part"]
    box = Part.makeBox(10.0, 10.0, 10.0)
    cylinder = Part.makeCylinder(2.0, 10.0, App.Vector(5.0, 5.0, 0.0))
    boolean = box.cut(cylinder)
    expected = 1000.0 - math.pi * 40.0
    check(not boolean.isNull(), "boolean result is null")
    check(boolean.isValid(), "boolean result is invalid")
    check(abs(boolean.Volume - expected) < 1.0e-6, "boolean volume mismatch")
    STATE["shape"] = boolean
    return {
        "boxVolume": box.Volume,
        "cylinderVolume": cylinder.Volume,
        "booleanVolume": boolean.Volume,
    }


def test_fcstd():
    App = STATE["App"]
    document = App.newDocument("HarmonyAcceptance")
    feature = document.addObject("Part::Feature", "Boolean")
    feature.Shape = STATE["shape"]
    document.recompute()
    path = OUTPUT_DIR / "acceptance.FCStd"
    document.saveAs(str(path))
    App.closeDocument(document.Name)

    reopened = App.openDocument(str(path))
    restored = reopened.getObject("Boolean")
    check(restored is not None and not restored.Shape.isNull(), "FCStd shape was not restored")
    volume = restored.Shape.Volume
    check(abs(volume - STATE["shape"].Volume) < 1.0e-6, "FCStd volume changed")
    App.closeDocument(reopened.Name)
    return {"bytes": path.stat().st_size, "volume": volume}


def test_step():
    App = STATE["App"]
    Import = STATE["Import"]
    path = OUTPUT_DIR / "acceptance.step"
    export_document = App.newDocument("StepExport")
    feature = export_document.addObject("Part::Feature", "Boolean")
    feature.Shape = STATE["shape"]
    export_document.recompute()
    Import.export([feature], str(path))
    App.closeDocument(export_document.Name)
    check(path.stat().st_size > 0, "STEP output is empty")

    import_document = App.newDocument("StepImport")
    Import.insert(str(path), import_document.Name)
    import_document.recompute()
    shapes = [obj.Shape for obj in import_document.Objects if hasattr(obj, "Shape")]
    check(shapes and all(not shape.isNull() for shape in shapes), "STEP readback has no shape")
    volume = sum(shape.Volume for shape in shapes)
    check(volume > 0.0, "STEP readback volume is empty")
    App.closeDocument(import_document.Name)
    return {"bytes": path.stat().st_size, "shapeCount": len(shapes), "volume": volume}


def test_stl():
    App = STATE["App"]
    Mesh = STATE["Mesh"]
    path = OUTPUT_DIR / "acceptance.stl"
    document = App.newDocument("StlExport")
    feature = document.addObject("Part::Feature", "Boolean")
    feature.Shape = STATE["shape"]
    document.recompute()
    Mesh.export([feature], str(path))
    App.closeDocument(document.Name)
    check(path.stat().st_size > 0, "STL output is empty")

    mesh = Mesh.Mesh(str(path))
    check(mesh.CountFacets > 0 and mesh.CountPoints > 0, "STL readback has no geometry")
    return {
        "bytes": path.stat().st_size,
        "facets": mesh.CountFacets,
        "points": mesh.CountPoints,
    }


OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
try:
    prepare_freecad_layout()
    run_test("occt_cpp_boolean_step", test_occt_cpp)
    run_test("freecad_module_imports", test_imports)
    run_test("part_box_cylinder_boolean", test_geometry)
    run_test("fcstd_save_reopen", test_fcstd)
    run_test("step_write_read", test_step)
    run_test("stl_export_read", test_stl)
except Exception as error:
    TESTS.append(
        {
            "name": "runtime_setup",
            "ok": False,
            "error": f"{type(error).__name__}: {error}",
            "traceback": traceback.format_exc(),
        }
    )

result = {
    "ok": all(test["ok"] for test in TESTS),
    "outputDir": str(OUTPUT_DIR),
    "tests": TESTS,
}
RESULT_PATH.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
