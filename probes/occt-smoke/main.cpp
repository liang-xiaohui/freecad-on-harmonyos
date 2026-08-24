#include <BRepAlgoAPI_Cut.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <TopoDS_Shape.hxx>

#include <cmath>
#include <iostream>

int main(int argc, char** argv)
{
    const char* output = argc > 1 ? argv[1] : "occt-smoke.step";
    const TopoDS_Shape box = BRepPrimAPI_MakeBox(20.0, 20.0, 20.0).Shape();
    const TopoDS_Shape cutter = BRepPrimAPI_MakeBox(gp_Pnt(5.0, 5.0, 5.0), 20.0, 20.0, 20.0).Shape();
    const TopoDS_Shape result = BRepAlgoAPI_Cut(box, cutter).Shape();

    if (result.IsNull()) {
        std::cerr << "boolean result is null\n";
        return 1;
    }

    GProp_GProps properties;
    BRepGProp::VolumeProperties(result, properties);
    if (!std::isfinite(properties.Mass()) || properties.Mass() <= 0.0) {
        std::cerr << "invalid result volume\n";
        return 2;
    }

    STEPControl_Writer writer;
    if (writer.Transfer(result, STEPControl_AsIs) != IFSelect_RetDone ||
        writer.Write(output) != IFSelect_RetDone) {
        std::cerr << "STEP write failed\n";
        return 3;
    }

    STEPControl_Reader reader;
    if (reader.ReadFile(output) != IFSelect_RetDone || reader.TransferRoots() == 0 ||
        reader.OneShape().IsNull()) {
        std::cerr << "STEP readback failed\n";
        return 4;
    }

    std::cout << "occt-smoke ok volume=" << properties.Mass() << " output=" << output << '\n';
    return 0;
}
