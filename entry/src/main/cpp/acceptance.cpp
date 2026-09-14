#include <Python.h>

#include <BRepAlgoAPI_Cut.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <Standard_Failure.hxx>
#include <TopoDS_Shape.hxx>

#include <dlfcn.h>
#include <dirent.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <rawfile/raw_file.h>
#include <rawfile/raw_file_manager.h>
#include <sys/stat.h>
#include <unistd.h>

#include <zlib.h>

#include <cerrno>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cxxabi.h>
#include <exception>
#include <fstream>
#include <signal.h>
#include <unwind.h>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr unsigned int PROBE_LOG_DOMAIN = 0x3202;
constexpr const char* PROBE_LOG_TAG = "FreeCADProbe";
std::mutex pythonMutex;
// FreeCAD and the embedded interpreter consume process-global cwd/environment
// state. Keep each native task's runtime setup and execution in one critical
// section so concurrent Want/NAPI calls cannot cross-contaminate jobs.
std::mutex runtimeMutex;
std::atomic_bool pythonInitialized {false};
std::mutex openGLMutex;
void* gl4esHandle = nullptr;

std::string writeGuiStartupScript(const std::string& filesDir);

struct AcceptanceWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    NativeResourceManager* resourceManager = nullptr;
    std::string outputDir;
    std::string result;
    std::string error;
};

std::string parentDirectory(const std::string& path)
{
    const std::string::size_type slash = path.find_last_of('/');
    if (slash == std::string::npos) {
        throw std::runtime_error("native library path has no parent directory");
    }
    return path.substr(0, slash);
}

std::string libraryRoot()
{
    Dl_info info {};
    if (dladdr(reinterpret_cast<void*>(&libraryRoot), &info) == 0 || info.dli_fname == nullptr) {
        throw std::runtime_error("dladdr failed for libfreecadacceptance.so");
    }
    return parentDirectory(info.dli_fname);
}

// QAbilityStage::setAppArgsFromWant() is handed ApplicationContext.filesDir,
// which is one level above the UIAbility files directory used by
// setupFreecadEnv(): <app>/files versus <app>/haps/<module>/files. QPA snapshots
// the argv of whichever caller reaches it first, and both orders have been
// observed on device, so the script path FreeCAD is asked to execute can be
// derived from either directory. Map a UIAbility files directory to its
// application-level counterpart.
std::string applicationFilesDirectory(const std::string& filesDir)
{
    return parentDirectory(parentDirectory(parentDirectory(filesDir))) + "/files";
}

// The HarmonyOS OpenGL wrapper reads NEED_OPENGL while the Qt/QPA application
// is being initialized.  QAbilityStage performs that initialization before
// QAbility::onCreate() can prepare the FreeCAD runtime, so keep this setup in
// a small idempotent entry point that can run at the start of the stage.
// Diagnostic: SIGABRT crashes (e.g. Preferences dialog) are invisible in
// hilog. Log the active exception before the runtime aborts.
void installTerminateProbe()
{
    std::set_terminate([]() {
        std::type_info* type = __cxxabiv1::__cxa_current_exception_type();
        if (type != nullptr) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                         "std::terminate, exception type=%{public}s", type->name());
            try {
                std::rethrow_exception(std::current_exception());
            }
            catch (const std::exception& error) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "std::terminate, what=%{public}s", error.what());
            }
            catch (...) {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "std::terminate, non-std exception");
            }
        }
        else {
            OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                         "std::terminate without active exception (plain abort?)");
        }
        std::abort();
    });
}

// Diagnostic: the DFX crash report lands in /data/log/faultlog which the hdc
// shell cannot read, so unwind fatal signals ourselves into hilog.
struct CrashBacktraceState {
    int count = 0;
};

_Unwind_Reason_Code crashBacktraceCallback(struct _Unwind_Context* context, void* arg)
{
    auto* state = static_cast<CrashBacktraceState*>(arg);
    uintptr_t pc = _Unwind_GetIP(context);
    if (pc == 0 || state->count >= 40) {
        return _URC_END_OF_STACK;
    }
    Dl_info info;
    if (dladdr(reinterpret_cast<void*>(pc), &info) != 0 && info.dli_fname != nullptr) {
        const char* symbol = info.dli_sname != nullptr ? info.dli_sname : "?";
        uintptr_t offset = info.dli_saddr != nullptr
            ? pc - reinterpret_cast<uintptr_t>(info.dli_saddr)
            : pc - reinterpret_cast<uintptr_t>(info.dli_fbase);
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "crash frame %{public}02d: %{public}s %{public}s+0x%{public}x",
                     state->count, info.dli_fname, symbol, (unsigned int)offset);
    }
    else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "crash frame %{public}02d: pc=0x%{public}x",
                     state->count, (unsigned int)pc);
    }
    ++state->count;
    return _URC_NO_REASON;
}

void crashSignalHandler(int signo, siginfo_t* siginfo, void*)
{
    OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                 "crash signal %{public}d addr=0x%{public}x, backtrace:",
                 signo, (unsigned int)(uintptr_t)(siginfo != nullptr ? siginfo->si_addr : nullptr));
    CrashBacktraceState state;
    _Unwind_Backtrace(crashBacktraceCallback, &state);
    signal(signo, SIG_DFL);
    raise(signo);
}

void installCrashSignalProbe()
{
    struct sigaction action {};
    action.sa_sigaction = crashSignalHandler;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGABRT, &action, nullptr);
    sigaction(SIGSEGV, &action, nullptr);
    sigaction(SIGBUS, &action, nullptr);
    sigaction(SIGILL, &action, nullptr);
}

void prepareOpenGLRuntime()
{
    std::lock_guard<std::mutex> guard(openGLMutex);
    setenv("NEED_OPENGL", "1", 1);
    setenv("LIBGL_NOTEST", "1", 1);

    if (gl4esHandle != nullptr) {
        return;
    }

    const std::string root = libraryRoot();
    const std::string libGL = root + "/libGL.so";
    gl4esHandle = dlopen(libGL.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (gl4esHandle == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "prepareOpenGL libGL.so dlopen FAILED: %{public}s", dlerror());
        return;
    }

    using InitGl4esFn = void (*)();
    auto initFn = reinterpret_cast<InitGl4esFn>(dlsym(gl4esHandle, "initialize_gl4es"));
    if (initFn != nullptr) {
        initFn();
        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "prepareOpenGL NEED_OPENGL=%{public}s initialize_gl4es OK",
                     std::getenv("NEED_OPENGL"));
    }
    else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "prepareOpenGL initialize_gl4es dlsym FAILED: %{public}s", dlerror());
    }
}

void requireDirectory(const std::string& path)
{
    struct stat status {};
    if (stat(path.c_str(), &status) != 0 || !S_ISDIR(status.st_mode)) {
        throw std::runtime_error("output directory is unavailable: " + path);
    }
}

void ensureDirectory(const std::string& path)
{
    if (mkdir(path.c_str(), 0700) != 0 && errno != EEXIST) {
        throw std::runtime_error("cannot create runtime directory: " + path + ": " +
                                 std::strerror(errno));
    }
    requireDirectory(path);
}

struct StalePreference {
    const char* element;
    const char* name;
    const char* value;
};

bool isStalePreferenceLine(const std::string& line, const StalePreference& preference)
{
    const std::string element = std::string("<") + preference.element;
    const std::string name = std::string("Name=\"") + preference.name + "\"";
    if (line.find(element) == std::string::npos || line.find(name) == std::string::npos) {
        return false;
    }

    constexpr const char* valueMarker = "Value=\"";
    const size_t valueBegin = line.find(valueMarker);
    if (valueBegin == std::string::npos) {
        return false;
    }
    const size_t valueStart = valueBegin + std::strlen(valueMarker);
    const size_t valueEnd = line.find('"', valueStart);
    if (valueEnd == std::string::npos) {
        return false;
    }
    const std::string value = line.substr(valueStart, valueEnd - valueStart);
    if (std::strcmp(preference.element, "FCFloat") != 0) {
        return value == preference.value;
    }

    char* parsedEnd = nullptr;
    const double parsed = std::strtod(value.c_str(), &parsedEnd);
    return parsedEnd != value.c_str() && *parsedEnd == '\0' &&
           parsed == std::strtod(preference.value, nullptr);
}

// Remove only values written by an older OHOS default. Each migration has an
// independent marker so adding a new default cannot replay earlier migrations
// and erase a choice the user made afterwards.
void dropStalePreferences(const std::string& home,
                          const char* markerName,
                          const std::vector<StalePreference>& preferences,
                          const char* reason)
{
    const std::string markerPath = home + "/" + markerName;
    struct stat markerStat {};
    if (stat(markerPath.c_str(), &markerStat) == 0) {
        return;
    }

    // Stale entries can only live in user.cfg; if it does not exist yet there
    // is nothing to migrate. Either way, never run this again so later
    // explicit user choices are preserved.
    const std::string cfgPath = home + "/user.cfg";
    std::ifstream input(cfgPath);
    if (!input) {
        std::ofstream marker(markerPath, std::ios::trunc);
        marker << "no user.cfg\n";
        return;
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    input.close();
    std::string content = buffer.str();
    bool changed = false;
    for (const StalePreference& preference : preferences) {
        size_t searchFrom = 0;
        const std::string name = std::string("Name=\"") + preference.name + "\"";
        while (true) {
            const size_t pos = content.find(name, searchFrom);
            if (pos == std::string::npos) {
                break;
            }
            const size_t previousNewline = content.rfind('\n', pos);
            const size_t lineBegin = previousNewline == std::string::npos ? 0 : previousNewline + 1;
            const size_t newline = content.find('\n', pos);
            const size_t lineEnd = newline == std::string::npos ? content.size() : newline + 1;
            const std::string line = content.substr(lineBegin, lineEnd - lineBegin);
            if (!isStalePreferenceLine(line, preference)) {
                searchFrom = lineEnd;
                continue;
            }
            content.erase(lineBegin, lineEnd - lineBegin);
            searchFrom = lineBegin;
            changed = true;
        }
    }
    if (changed) {
        std::ofstream output(cfgPath, std::ios::trunc);
        output << content;
        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "dropped stale user.cfg entries: %{public}s", reason);
    }
    std::ofstream marker(markerPath, std::ios::trunc);
    marker << (changed ? "migrated\n" : "nothing-to-migrate\n");
}

struct WritableRuntimePaths {
    std::string home;
    std::string data;
    std::string cache;
    std::string temp;
};

WritableRuntimePaths configureWritableRuntime(const std::string& outputDir)
{
    WritableRuntimePaths paths {
        outputDir + "/freecad-home",
        outputDir + "/freecad-data",
        outputDir + "/freecad-cache",
        outputDir + "/freecad-temp",
    };
    ensureDirectory(paths.home);
    ensureDirectory(paths.data);
    ensureDirectory(paths.cache);
    ensureDirectory(paths.temp);
    dropStalePreferences(paths.home,
                         ".prefs-migrated-20260904",
                         {{"FCBool", "MakeInternals", "0"},
                          {"FCBool", "ShowAxisCross", "0"}},
                         "MakeInternals/ShowAxisCross (old off-by-default values)");
    dropStalePreferences(paths.home,
                         ".pick-radius-migrated-20260904",
                         {{"FCFloat", "PickRadius", "5"}},
                         "PickRadius (old 5px default)");

    // FreeCAD may fall back to the process working directory when Qt cannot
    // resolve a platform standard path. The bundle directory is read-only on
    // HarmonyOS, so keep both the cwd and every standard path app-private.
    if (chdir(outputDir.c_str()) != 0) {
        throw std::runtime_error("cannot switch to writable runtime directory: " + outputDir);
    }
    setenv("HOME", paths.home.c_str(), 1);
    setenv("TMPDIR", paths.temp.c_str(), 1);
    setenv("XDG_CONFIG_HOME", paths.home.c_str(), 1);
    setenv("XDG_DATA_HOME", paths.data.c_str(), 1);
    setenv("XDG_CACHE_HOME", paths.cache.c_str(), 1);
    setenv("FREECAD_USER_HOME", paths.home.c_str(), 1);
    setenv("FREECAD_USER_DATA", paths.data.c_str(), 1);
    setenv("FREECAD_USER_TEMP", paths.temp.c_str(), 1);

    // TLS trust store. CPython's _ssl links against the OHOS OpenSSL build,
    // whose compiled-in OPENSSLDIR is the CPPLib build prefix - a host path
    // that does not exist inside the app sandbox, so every HTTPS request would
    // fail with CERTIFICATE_VERIFY_FAILED. Point OpenSSL at a readable bundle.
    // The system bundle is read-only and OS-maintained; the fallback ships in
    // the runtime archive (freecad-home/share/cacert.pem) and may only appear
    // once the background materialize worker has unpacked it.
    const char* systemCaBundle = "/etc/ssl/certs/cacert.pem";
    const std::string bundledCaBundle = paths.home + "/share/cacert.pem";
    if (access(systemCaBundle, R_OK) == 0) {
        setenv("SSL_CERT_FILE", systemCaBundle, 1);
        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "SSL_CERT_FILE=%{public}s (system bundle)", systemCaBundle);
    }
    else {
        setenv("SSL_CERT_FILE", bundledCaBundle.c_str(), 1);
        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "SSL_CERT_FILE=%{public}s (bundled fallback)", bundledCaBundle.c_str());
    }
    if (access("/etc/ssl/certs", R_OK) == 0) {
        setenv("SSL_CERT_DIR", "/etc/ssl/certs", 1);
    }
    return paths;
}

void copyRawFile(NativeResourceManager* manager, const char* rawName,
                 const std::string& destination, bool reuseExisting)
{
    RawFile* raw = OH_ResourceManager_OpenRawFile(manager, rawName);
    if (raw == nullptr) {
        throw std::runtime_error(std::string("cannot open rawfile: ") + rawName);
    }

    const long rawSize = OH_ResourceManager_GetRawFileSize(raw);
    struct stat existing {};
    if (reuseExisting && rawSize > 0 && stat(destination.c_str(), &existing) == 0 &&
        existing.st_size == rawSize) {
        OH_ResourceManager_CloseRawFile(raw);
        return;
    }

    const std::string temporary = destination + ".new";
    FILE* output = fopen(temporary.c_str(), "wb");
    if (output == nullptr) {
        OH_ResourceManager_CloseRawFile(raw);
        throw std::runtime_error("cannot create runtime file: " + temporary);
    }

    char buffer[64 * 1024];
    long total = 0;
    bool failed = false;
    while (total < rawSize) {
        const int count = OH_ResourceManager_ReadRawFile(raw, buffer, sizeof(buffer));
        if (count <= 0 || fwrite(buffer, 1, static_cast<size_t>(count), output) !=
                              static_cast<size_t>(count)) {
            failed = true;
            break;
        }
        total += count;
    }
    if (fclose(output) != 0) {
        failed = true;
    }
    OH_ResourceManager_CloseRawFile(raw);

    if (failed || total != rawSize || rename(temporary.c_str(), destination.c_str()) != 0) {
        unlink(temporary.c_str());
        throw std::runtime_error(std::string("cannot materialize rawfile: ") + rawName);
    }
}

// 递归复制目录（POSIX，用于把 lib-dynload 复制进 python home 布局）。
// 避免 std::filesystem（OHOS musl + libc++ 下兼容性存疑）。
void copyDirectoryTree(const std::string& from, const std::string& to)
{
    DIR* dir = opendir(from.c_str());
    if (dir == nullptr) {
        throw std::runtime_error("cannot open source directory: " + from);
    }
    ensureDirectory(to);
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        const std::string srcPath = from + "/" + entry->d_name;
        const std::string dstPath = to + "/" + entry->d_name;
        struct stat st {};
        if (lstat(srcPath.c_str(), &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            copyDirectoryTree(srcPath, dstPath);
        }
        else if (S_ISREG(st.st_mode)) {
            std::ifstream in(srcPath, std::ios::binary);
            if (!in) {
                closedir(dir);
                throw std::runtime_error("cannot read source file: " + srcPath);
            }
            std::ofstream out(dstPath, std::ios::binary);
            if (!out) {
                closedir(dir);
                throw std::runtime_error("cannot create destination file: " + dstPath);
            }
            out << in.rdbuf();
        }
    }
    closedir(dir);
}

// 复制单个文件（POSIX）。用于从 HAP libs 目录（root）直接读文件，绕过 isolationProcess 里
// resourceManager 读 rawfile 可能失败/返回 0 大小的问题。
void copyFile(const std::string& from, const std::string& to)
{
    std::ifstream in(from, std::ios::binary);
    if (!in) {
        throw std::runtime_error("cannot open source file: " + from);
    }
    std::ofstream out(to, std::ios::binary);
    if (!out) {
        throw std::runtime_error("cannot create destination file: " + to);
    }
    out << in.rdbuf();
    if (!out) {
        throw std::runtime_error("cannot write destination file: " + to);
    }
}

// 递归删除目录（POSIX）。用于删除旧复制目录后再建立符号链接。
void removeTree(const std::string& path)
{
    DIR* dir = opendir(path.c_str());
    if (dir == nullptr) {
        return;
    }
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        const std::string p = path + "/" + entry->d_name;
        struct stat st {};
        if (lstat(p.c_str(), &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            removeTree(p);
        }
        else {
            unlink(p.c_str());
        }
    }
    closedir(dir);
    rmdir(path.c_str());
}

std::string materializeRuntime(AcceptanceWork& acceptance)
{
    const std::string runtimeDir = acceptance.outputDir + "/runtime";
    ensureDirectory(runtimeDir);
    ensureDirectory(runtimeDir + "/lib");
    const bool reuseExisting = pythonInitialized.load(std::memory_order_acquire);
    copyRawFile(acceptance.resourceManager, "python311.zip", runtimeDir + "/lib/python311.zip",
                reuseExisting);
    // The Python runtime archive can change without changing its byte size
    // between HAP revisions. Refresh it on every launch so a persistent app
    // filesDir cannot retain older modules.
    copyRawFile(acceptance.resourceManager, "freecad-runtime.zip",
                runtimeDir + "/freecad-runtime.zip", false);
    copyRawFile(acceptance.resourceManager, "freecad_headless_acceptance.py",
                runtimeDir + "/freecad_headless_acceptance.py", reuseExisting);
    return runtimeDir;
}

std::string readFile(const std::string& path)
{
    std::ifstream stream(path);
    if (!stream) {
        throw std::runtime_error("cannot read acceptance result: " + path);
    }
    std::ostringstream contents;
    contents << stream.rdbuf();
    return contents.str();
}

std::string pythonObjectText(PyObject* object)
{
    if (object == nullptr) {
        return {};
    }

    PyObject* text = PyObject_Str(object);
    if (text == nullptr) {
        PyErr_Clear();
        return {};
    }

    const char* utf8 = PyUnicode_AsUTF8(text);
    const std::string result = utf8 == nullptr ? std::string() : std::string(utf8);
    Py_DECREF(text);
    if (PyErr_Occurred()) {
        PyErr_Clear();
    }
    return result;
}

std::string fetchPythonError()
{
    if (!PyErr_Occurred()) {
        return {};
    }

    PyObject* type = nullptr;
    PyObject* value = nullptr;
    PyObject* traceback = nullptr;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);

    std::string formatted;
    PyObject* tracebackModule = PyImport_ImportModule("traceback");
    if (tracebackModule != nullptr) {
        PyObject* lines = PyObject_CallMethod(tracebackModule, "format_exception", "OOO", type,
                                               value, traceback);
        if (lines != nullptr) {
            PyObject* separator = PyUnicode_FromString("");
            if (separator != nullptr) {
                PyObject* joined = PyObject_CallMethod(separator, "join", "O", lines);
                formatted = pythonObjectText(joined);
                Py_XDECREF(joined);
                Py_DECREF(separator);
            }
            Py_DECREF(lines);
        }
        Py_DECREF(tracebackModule);
    }
    PyErr_Clear();

    if (formatted.empty()) {
        const std::string typeText = pythonObjectText(type);
        const std::string valueText = pythonObjectText(value);
        formatted = typeText;
        if (!valueText.empty()) {
            if (!formatted.empty()) {
                formatted += ": ";
            }
            formatted += valueText;
        }
    }

    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    return formatted;
}

std::string jsonEscape(const std::string& value)
{
    std::string escaped;
    escaped.reserve(value.size() + 16);
    for (const unsigned char character : value) {
        switch (character) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                if (character < 0x20) {
                    char control[7] {};
                    std::snprintf(control, sizeof(control), "\\u%04x", character);
                    escaped += control;
                }
                else {
                    escaped += static_cast<char>(character);
                }
                break;
        }
    }
    return escaped;
}

void writePythonFailureResult(const std::string& path, const std::string& outputDir,
                              int runStatus, const std::string& pythonError)
{
    std::ofstream stream(path, std::ios::trunc);
    if (!stream) {
        return;
    }
    const std::string detail = "Python script status=" + std::to_string(runStatus) +
                               (pythonError.empty() ? std::string() : "\n" + pythonError);
    stream << "{\n"
           << "  \"ok\": false,\n"
           << "  \"outputDir\": \"" << jsonEscape(outputDir) << "\",\n"
           << "  \"tests\": [{\"name\": \"python_entry\", \"ok\": false, \"error\": \""
           << jsonEscape(detail) << "\"}]\n"
           << "}\n";
}

void syncPythonEnvironment(const std::string& root, const std::string& outputDir,
                           const WritableRuntimePaths& paths)
{
    PyObject* osModule = PyImport_ImportModule("os");
    if (osModule == nullptr) {
        throw std::runtime_error("cannot import Python os module");
    }
    PyObject* environment = PyObject_GetAttrString(osModule, "environ");
    Py_DECREF(osModule);
    if (environment == nullptr) {
        PyErr_Clear();
        throw std::runtime_error("cannot access Python os.environ");
    }

    const std::string resourceDir = paths.home + "/share";
    const char* keys[] = {
        "FREECAD_PROBE_OUTPUT_DIR",
        "FREECAD_USER_HOME",
        "FREECAD_USER_DATA",
        "FREECAD_USER_TEMP",
        "HOME",
        "TMPDIR",
        "XDG_CONFIG_HOME",
        "XDG_DATA_HOME",
        "XDG_CACHE_HOME",
        "FREECAD_APP_HOME",
        "FREECAD_APP_LIBRARY_DIR",
        "FREECAD_APP_RESOURCE_DIR",
        "FREECAD_PROBE_ROOT",
        "FREECAD_OCCT_SMOKE_VOLUME",
        "FLEXIMIND_FILES_DIR",
    };
    const char* values[] = {
        outputDir.c_str(),
        paths.home.c_str(),
        paths.data.c_str(),
        paths.temp.c_str(),
        paths.home.c_str(),
        paths.temp.c_str(),
        paths.home.c_str(),
        paths.data.c_str(),
        paths.cache.c_str(),
        root.c_str(),
        root.c_str(),
        resourceDir.c_str(),
        std::getenv("FREECAD_PROBE_ROOT"),
        std::getenv("FREECAD_OCCT_SMOKE_VOLUME"),
        std::getenv("FLEXIMIND_FILES_DIR"),
    };
    for (size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); ++index) {
        if (values[index] == nullptr) {
            continue;
        }
        PyObject* key = PyUnicode_FromString(keys[index]);
        PyObject* value = PyUnicode_FromString(values[index]);
        const int status = key == nullptr || value == nullptr
                               ? -1
                               : PyObject_SetItem(environment, key, value);
        Py_XDECREF(key);
        Py_XDECREF(value);
        if (status != 0) {
            Py_DECREF(environment);
            PyErr_Clear();
            throw std::runtime_error("cannot update Python os.environ");
        }
    }
    Py_DECREF(environment);
}

double runOcctSmoke(const std::string& outputDir)
{
    const TopoDS_Shape box = BRepPrimAPI_MakeBox(20.0, 20.0, 20.0).Shape();
    const TopoDS_Shape cutter =
        BRepPrimAPI_MakeBox(gp_Pnt(5.0, 5.0, 5.0), 20.0, 20.0, 20.0).Shape();
    const TopoDS_Shape result = BRepAlgoAPI_Cut(box, cutter).Shape();
    if (result.IsNull()) {
        throw std::runtime_error("OCCT boolean result is null");
    }

    GProp_GProps properties;
    BRepGProp::VolumeProperties(result, properties);
    const double volume = properties.Mass();
    if (!std::isfinite(volume) || volume <= 0.0) {
        throw std::runtime_error("OCCT boolean volume is invalid");
    }

    const std::string stepPath = outputDir + "/occt-smoke.step";
    STEPControl_Writer writer;
    if (writer.Transfer(result, STEPControl_AsIs) != IFSelect_RetDone ||
        writer.Write(stepPath.c_str()) != IFSelect_RetDone) {
        throw std::runtime_error("OCCT STEP write failed");
    }

    STEPControl_Reader reader;
    if (reader.ReadFile(stepPath.c_str()) != IFSelect_RetDone || reader.TransferRoots() == 0 ||
        reader.OneShape().IsNull()) {
        throw std::runtime_error("OCCT STEP readback failed");
    }
    return volume;
}

void appendModulePath(PyConfig& config, const std::string& path)
{
    wchar_t* widePath = Py_DecodeLocale(path.c_str(), nullptr);
    if (widePath == nullptr) {
        throw std::runtime_error("cannot decode Python module path: " + path);
    }
    const PyStatus status = PyWideStringList_Append(&config.module_search_paths, widePath);
    PyMem_RawFree(widePath);
    if (PyStatus_Exception(status)) {
        throw std::runtime_error("cannot append Python module path: " + path);
    }
}

void initializePython(const std::string& root, const std::string& runtimeDir)
{
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.install_signal_handlers = 0;
    config.parse_argv = 0;
    config.site_import = 0;
    config.write_bytecode = 0;
    config.module_search_paths_set = 1;

    PyStatus status = PyConfig_SetBytesString(&config, &config.home, root.c_str());
    if (!PyStatus_Exception(status)) {
        const std::string executable = root + "/FreeCADProbe";
        status = PyConfig_SetBytesString(&config, &config.program_name, executable.c_str());
    }
    if (PyStatus_Exception(status)) {
        PyConfig_Clear(&config);
        throw std::runtime_error("cannot configure embedded Python");
    }

    try {
        appendModulePath(config, runtimeDir + "/lib/python311.zip");
        appendModulePath(config, root + "/lib/python3.11/lib-dynload");
        appendModulePath(config, root);
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Ext");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/Part");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/Mesh");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/Import");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/Material");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/Sketcher");
        appendModulePath(config, runtimeDir + "/freecad-runtime.zip/Mod/PartDesign");
    }
    catch (...) {
        PyConfig_Clear(&config);
        throw;
    }

    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        throw std::runtime_error("Py_InitializeFromConfig failed");
    }
    pythonInitialized.store(true, std::memory_order_release);
}

std::string runPythonAcceptance(const std::string& root, const std::string& runtimeDir,
                                const std::string& outputDir, const WritableRuntimePaths& paths)
{
    std::lock_guard<std::mutex> guard(pythonMutex);
    const std::string resultPath = outputDir + "/freecad-acceptance.json";
    const std::string scriptPath = runtimeDir + "/freecad_headless_acceptance.py";
    unlink(resultPath.c_str());

    // CPython snapshots the process environment while it initializes os.environ.
    // These values must be present before the first Py_InitializeFromConfig call.
    setenv("FREECAD_PROBE_OUTPUT_DIR", outputDir.c_str(), 1);
    setenv("FREECAD_APP_HOME", paths.home.c_str(), 1);
    setenv("FREECAD_APP_LIBRARY_DIR", root.c_str(), 1);
    setenv("FREECAD_APP_RESOURCE_DIR", (outputDir + "/freecad-home/share").c_str(), 1);
    setenv("FREECAD_USER_HOME", paths.home.c_str(), 1);
    setenv("FREECAD_USER_DATA", paths.data.c_str(), 1);
    setenv("FREECAD_USER_TEMP", paths.temp.c_str(), 1);

    const bool firstRun = !pythonInitialized.load(std::memory_order_acquire);
    if (firstRun) {
        initializePython(root, runtimeDir);
    }

    PyGILState_STATE gilState {};
    if (!firstRun) {
        gilState = PyGILState_Ensure();
    }

    try {
        syncPythonEnvironment(root, outputDir, paths);
    }
    catch (...) {
        if (firstRun) {
            PyEval_SaveThread();
        }
        else {
            PyGILState_Release(gilState);
        }
        throw;
    }

    FILE* script = fopen(scriptPath.c_str(), "r");
    if (script == nullptr) {
        if (firstRun) {
            PyEval_SaveThread();
        }
        else {
            PyGILState_Release(gilState);
        }
        throw std::runtime_error("cannot open Python acceptance script: " + scriptPath);
    }

    PyObject* mainModule = PyImport_AddModule("__main__");
    PyObject* mainGlobals = mainModule == nullptr ? nullptr : PyModule_GetDict(mainModule);
    PyObject* execution = mainGlobals == nullptr
                              ? nullptr
                              : PyRun_FileExFlags(script, scriptPath.c_str(), Py_file_input,
                                                  mainGlobals, mainGlobals, 1, nullptr);
    const int runStatus = execution == nullptr ? -1 : 0;
    Py_XDECREF(execution);
    const std::string pythonError = fetchPythonError();

    if (firstRun) {
        PyEval_SaveThread();
    }
    else {
        PyGILState_Release(gilState);
    }

    if (access(resultPath.c_str(), R_OK) != 0) {
        writePythonFailureResult(resultPath, outputDir, runStatus, pythonError);
        const std::string detail = pythonError.empty()
                                        ? "Python acceptance script failed without a result file"
                                        : "Python acceptance script failed: " + pythonError;
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "Python failure status=%{public}d detail=%{public}s", runStatus,
                     detail.c_str());
        return readFile(resultPath);
    }
    if (runStatus != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "Python acceptance script returned status=%{public}d", runStatus);
    }
    const std::string resultJson = readFile(resultPath);
    // 成功路径也打印结果 JSON，便于 hilog 直接核对 6 项验收（设备屏幕上只显示 ok 布尔）。
    OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                 "Python acceptance result status=%{public}d json=%{public}s", runStatus,
                 resultJson.c_str());
    return resultJson;
}

void executeAcceptance(napi_env, void* data)
{
    auto* acceptance = static_cast<AcceptanceWork*>(data);
    std::lock_guard<std::mutex> runtimeGuard(runtimeMutex);
    try {
        requireDirectory(acceptance->outputDir);
        const WritableRuntimePaths writablePaths = configureWritableRuntime(acceptance->outputDir);
        const std::string root = libraryRoot();
        const std::string runtimeDir = materializeRuntime(*acceptance);
        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "acceptance root=%{public}s output=%{public}s", root.c_str(),
                     acceptance->outputDir.c_str());

        const double occtVolume = runOcctSmoke(acceptance->outputDir);
        const std::string volumeText = std::to_string(occtVolume);
        setenv("FREECAD_OCCT_SMOKE_VOLUME", volumeText.c_str(), 1);
        setenv("FREECAD_PROBE_ROOT", root.c_str(), 1);
        acceptance->result = runPythonAcceptance(root, runtimeDir, acceptance->outputDir, writablePaths);
    }
    catch (const Standard_Failure& error) {
        acceptance->error = std::string("OCCT failure: ") + error.GetMessageString();
    }
    catch (const std::exception& error) {
        acceptance->error = error.what();
    }
}

void completeAcceptance(napi_env env, napi_status status, void* data)
{
    auto* acceptance = static_cast<AcceptanceWork*>(data);
    if (status != napi_ok && acceptance->error.empty()) {
        acceptance->error = "NAPI async work failed";
    }

    if (acceptance->error.empty()) {
        napi_value result;
        napi_create_string_utf8(env, acceptance->result.c_str(), acceptance->result.size(), &result);
        napi_resolve_deferred(env, acceptance->deferred, result);
    }
    else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG, "%{public}s",
                     acceptance->error.c_str());
        napi_value message;
        napi_value error;
        napi_create_string_utf8(env, acceptance->error.c_str(), acceptance->error.size(), &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, acceptance->deferred, error);
    }

    OH_ResourceManager_ReleaseNativeResourceManager(acceptance->resourceManager);
    napi_delete_async_work(env, acceptance->work);
    delete acceptance;
}

napi_value runAcceptance(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr,
                              "runAcceptance expects the files directory and resource manager");
        return nullptr;
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "output directory must be a string");
        return nullptr;
    }

    auto* acceptance = new AcceptanceWork();
    acceptance->outputDir.resize(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, args[0], acceptance->outputDir.data(), acceptance->outputDir.size(), &copied) != napi_ok) {
        delete acceptance;
        napi_throw_type_error(env, nullptr, "cannot read output directory");
        return nullptr;
    }
    acceptance->outputDir.resize(copied);
    acceptance->resourceManager = OH_ResourceManager_InitNativeResourceManager(env, args[1]);
    if (acceptance->resourceManager == nullptr) {
        delete acceptance;
        napi_throw_type_error(env, nullptr, "cannot initialize the native resource manager");
        return nullptr;
    }

    napi_value promise;
    napi_create_promise(env, &acceptance->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "FreeCADAcceptance", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, executeAcceptance, completeAcceptance,
                           acceptance, &acceptance->work);
    napi_queue_async_work(env, acceptance->work);
    return promise;
}


// 供 QAbility（GUI）在启动 Qt 应用前调用：物化 rawfile 运行时并设置 FreeCAD 环境变量。
// 必须在 QAbility 进程内调用（与 QPA / Qt main 同进程，环境变量才能被 FreeCAD 看到）。

// 设置 FreeCAD 运行环境变量并把两个 rawfile zip 复制到可写目录。
// materializeFreecadRuntimeAsync 随后在 native async work 中用纯 C++/zlib 解压约 48MB；
// QAbility 会等 Promise 完成后才把 window stage 交给 QPA。
// 标准库 zip 必须在这里同步就位：FreeCAD 的 Interpreter::init 在 XComponent attach 后立即
// 初始化 Python，此刻异步 materialize worker 可能还没复制完 <PYTHONHOME>/lib/python311.zip。
napi_value prepareOpenGL(napi_env env, napi_callback_info info)
{
    (void)env;
    (void)info;
    try {
        prepareOpenGLRuntime();
    }
    catch (const std::exception& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
    return nullptr;
}

napi_value setupFreecadEnv(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> runtimeGuard(runtimeMutex);
    installTerminateProbe();
    installCrashSignalProbe();
    size_t argc = 2;
    napi_value args[2] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        napi_throw_type_error(env, nullptr, "setupFreecadEnv expects filesDir and resource manager");
        return nullptr;
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "files directory must be a string");
        return nullptr;
    }
    // napi_get_value_string_utf8 writes a trailing NUL when the buffer is sized
    // larger than the reported UTF-8 byte count.
    std::string filesDir(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, args[0], filesDir.data(), filesDir.size(), &copied) != napi_ok) {
        napi_throw_type_error(env, nullptr, "cannot read files directory");
        return nullptr;
    }
    filesDir.resize(copied);

    NativeResourceManager* manager = OH_ResourceManager_InitNativeResourceManager(env, args[1]);
    if (manager == nullptr) {
        napi_throw_type_error(env, nullptr, "cannot initialize the native resource manager");
        return nullptr;
    }

    try {
        const std::string root = libraryRoot();
        const std::string home = filesDir + "/freecad-home";
        const std::string runtimeDir = filesDir + "/runtime";
        // 建立可写目录 + chdir + HOME/TMPDIR/FREECAD_USER_*（全部快速操作）
        configureWritableRuntime(filesDir);
        // 标准库 zip 同步就位（<PYTHONHOME>/lib/python311.zip，getpath 固定查找位置）。
        ensureDirectory(runtimeDir);
        ensureDirectory(runtimeDir + "/lib");
        const std::string pyzip = runtimeDir + "/lib/python311.zip";
        // 诊断：isolationProcess 里 rawfile 读取可能返回 0 大小，导致复制出空 zip。
        {
            RawFile* raw = OH_ResourceManager_OpenRawFile(manager, "python311.zip");
            if (raw != nullptr) {
                const long rawSize = OH_ResourceManager_GetRawFileSize(raw);
                OH_ResourceManager_CloseRawFile(raw);
                OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip rawSize=%{public}ld", rawSize);
            }
            else {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip OpenRawFile FAILED");
            }
        }
        // 强制复制（reuseExisting=false），并校验大小：避免历史残留空文件被 reuse 跳过。
        copyRawFile(manager, "python311.zip", pyzip, false);
        // 同步复制 freecad-runtime.zip（~16MB，含工作台/PySide/Pivy/Coin 资源）。
        // 必须在主线程用 resourceManager 读 rawfile——后台 worker 无法初始化
        // resourceManager（会抛 "cannot initialize the native resource manager"），
        // 这正是之前 materialize 在后台一直失败、工作台资源缺失导致窗口闪退的根因。
        // 16MB 复制远快于 250MB 解压，主线程 <1s，不会触发 appFreeze。
        copyRawFile(manager, "freecad-runtime.zip", runtimeDir + "/freecad-runtime.zip", false);
        {
            struct stat st {};
            if (stat(pyzip.c_str(), &st) == 0) {
                OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip copied size=%{public}ld", (long)st.st_size);
            }
            else {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip MISSING after copy");
            }
            // 读回验证：确认文件在 isolationProcess 里可读且内容正确（PK 魔数 0x50 0x4b 0x03 0x04）。
            FILE* f = fopen(pyzip.c_str(), "rb");
            if (f != nullptr) {
                unsigned char magic[4] = {0};
                const size_t n = fread(magic, 1, 4, f);
                fclose(f);
                OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip magic=%{public}02x%{public}02x%{public}02x%{public}02x n=%{public}d",
                             magic[0], magic[1], magic[2], magic[3], (int)n);
            }
            else {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv python311.zip fopen FAILED errno=%{public}d", errno);
            }
        }
        // 关键修复：lib-dynload 定位到 root（HAP，有签名），而非 filesDir（复制丢签名 → dlopen 拒绝）。
        // 通过 PYTHONHOME=prefix:exec_prefix 让 getpath 把 lib-dynload 算到 exec_prefix(=root)。
        // 这里不再复制/符号链接 lib-dynload（跨目录 symlink 被沙箱拒绝，复制丢签名）。
        // 仅诊断验证 root 里的 zlib.so（有签名，Python 将 dlopen 它）。
        {
            const std::string zlibRootSo = root + "/lib/python3.11/lib-dynload/zlib.cpython-311-aarch64-linux-ohos.so";
            struct stat st {};
            if (stat(zlibRootSo.c_str(), &st) == 0) {
                void* zh = dlopen(zlibRootSo.c_str(), RTLD_NOW);
                if (zh != nullptr) {
                    OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                                 "setupFreecadEnv root zlib.so dlopen OK (size=%{public}ld)", (long)st.st_size);
                    dlclose(zh);
                }
                else {
                    OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                                 "setupFreecadEnv root zlib.so dlopen FAILED: %{public}s", dlerror());
                }
            }
            else {
                OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                             "setupFreecadEnv root zlib.so MISSING");
            }
        }
        // 关键修复：PYTHONHOME 用冒号分隔 "prefix:exec_prefix"。
        //   prefix  = filesDir/runtime（python311.zip 标准库在此，可写）
        //   exec_prefix = root（HAP libs 根，lib-dynload 在此，有 HAP 签名）
        // getpath 会据此把 lib-dynload 定位到 root（有签名），而不是 filesDir（复制会丢签名
        // 导致 dlopen "Permission denied"）。python311.zip 仍从 filesDir 读。
        setenv("PYTHONHOME", (runtimeDir + ":" + root).c_str(), 1);
        setenv("FREECAD_APP_HOME", home.c_str(), 1);
        setenv("FREECAD_APP_LIBRARY_DIR", root.c_str(), 1);
        setenv("FREECAD_APP_RESOURCE_DIR", (home + "/share").c_str(), 1);
        writeGuiStartupScript(filesDir);
        std::string libraryPath = root;
        if (const char* existing = std::getenv("LD_LIBRARY_PATH")) {
            libraryPath += ":";
            libraryPath += existing;
        }
        setenv("LD_LIBRARY_PATH", libraryPath.c_str(), 1);

        // gl4es must also be initialized before Qt/QPA.  Calling this here is
        // an idempotent fallback for headless callers and older launch paths.
        prepareOpenGLRuntime();

        OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "setupFreecadEnv root=%{public}s home=%{public}s NEED_OPENGL=%{public}s",
                     root.c_str(), home.c_str(), std::getenv("NEED_OPENGL"));
        OH_ResourceManager_ReleaseNativeResourceManager(manager);
        return nullptr;
    }
    catch (const std::exception& error) {
        OH_ResourceManager_ReleaseNativeResourceManager(manager);
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

// 最小 zip 解压（纯 C++/zlib），支持 stored(0) 与 deflate(8) 两种条目。
// 不使用嵌入式 Python，避免和 FreeCAD Qt 主线程的 Python 初始化发生竞态。
namespace {

uint16_t readLe16(const unsigned char* p)
{
    return static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8);
}

uint32_t readLe32(const unsigned char* p)
{
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8)
        | (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

bool writeAllBytes(const std::string& path, const unsigned char* data, size_t size)
{
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return false;
    }
    out.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(size));
    return out.good();
}

bool ensureParentDir(const std::string& filePath)
{
    const size_t slash = filePath.find_last_of('/');
    if (slash == std::string::npos) {
        return true;
    }
    const std::string parent = filePath.substr(0, slash);
    if (!parent.empty() && parent != "/") {
        ensureParentDir(parent);  // 递归创建多级父目录
        ensureDirectory(parent);
    }
    return true;
}

// 解压 zip 到 destDir。返回 true 表示全部条目成功。
bool extractZipToDir(const std::string& zipPath, const std::string& destDir)
{
    std::ifstream zf(zipPath, std::ios::binary);
    if (!zf) {
        return false;
    }
    std::vector<unsigned char> buf((std::istreambuf_iterator<char>(zf)),
                                   std::istreambuf_iterator<char>());
    zf.close();
    const size_t n = buf.size();
    if (n < 30) {
        return false;
    }

    size_t off = 0;
    bool sawAny = false;
    while (off + 30 <= n) {
        const uint32_t sig = readLe32(&buf[off]);
        if (sig == 0x06054b50) {  // EOCD，条目结束
            break;
        }
        if (sig != 0x04034b50) {  // 非 local file header，逐字节前移
            ++off;
            continue;
        }
        const uint16_t method = readLe16(&buf[off + 8]);
        const uint32_t compSize = readLe32(&buf[off + 18]);
        const uint32_t uncompSize = readLe32(&buf[off + 22]);
        const uint16_t nameLen = readLe16(&buf[off + 26]);
        const uint16_t extraLen = readLe16(&buf[off + 28]);
        const size_t headerSize = 30 + nameLen + extraLen;
        if (off + headerSize + compSize > n) {
            return false;
        }
        const std::string name(reinterpret_cast<const char*>(&buf[off + 30]), nameLen);
        const unsigned char* data = &buf[off + headerSize];

        if (name.empty() || name.back() == '/') {
            if (!name.empty()) {
                std::string dir = name;
                while (!dir.empty() && dir.back() == '/') {
                    dir.pop_back();
                }
                if (!dir.empty()) {
                    ensureParentDir(destDir + "/" + dir);
                    ensureDirectory(destDir + "/" + dir);
                }
            }
            off += headerSize + compSize;
            continue;
        }

        const std::string target = destDir + "/" + name;
        if (!ensureParentDir(target)) {
            return false;
        }
        if (method == 0) {  // stored
            if (!writeAllBytes(target, data, compSize)) {
                return false;
            }
        }
        else if (method == 8) {  // deflate（raw，无 zlib 头）
            std::vector<unsigned char> out(uncompSize);
            z_stream zs {};
            zs.next_in = const_cast<unsigned char*>(data);
            zs.avail_in = compSize;
            zs.next_out = out.data();
            zs.avail_out = uncompSize;
            if (inflateInit2(&zs, -15) != Z_OK) {
                return false;
            }
            const int r = inflate(&zs, Z_FINISH);
            inflateEnd(&zs);
            if (r != Z_STREAM_END) {
                return false;
            }
            if (!writeAllBytes(target, out.data(), uncompSize)) {
                return false;
            }
        }
        else {
            return false;  // 不支持的方法
        }
        sawAny = true;
        off += headerSize + compSize;
    }
    return sawAny;
}

std::string runtimeArchiveIdentity(const std::string& zipPath)
{
    std::ifstream stream(zipPath, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("cannot open FreeCAD runtime archive: " + zipPath);
    }

    uLong checksum = crc32(0L, Z_NULL, 0);
    unsigned long long total = 0;
    unsigned char buffer[64 * 1024];
    while (stream) {
        stream.read(reinterpret_cast<char*>(buffer), sizeof(buffer));
        const std::streamsize count = stream.gcount();
        if (count > 0) {
            checksum = crc32(checksum, buffer, static_cast<uInt>(count));
            total += static_cast<unsigned long long>(count);
        }
    }
    if (!stream.eof()) {
        throw std::runtime_error("cannot read FreeCAD runtime archive: " + zipPath);
    }
    return std::to_string(total) + ":" + std::to_string(static_cast<unsigned long>(checksum));
}

bool runtimeMarkerMatches(const std::string& markerPath, const std::string& identity)
{
    std::ifstream marker(markerPath);
    std::string storedIdentity;
    return marker && std::getline(marker, storedIdentity) && storedIdentity == identity;
}

void writeRuntimeMarker(const std::string& markerPath, const std::string& identity)
{
    const std::string temporary = markerPath + ".new";
    {
        std::ofstream marker(temporary, std::ios::trunc);
        if (!marker || !(marker << identity << '\n')) {
            unlink(temporary.c_str());
            throw std::runtime_error("cannot write FreeCAD runtime marker");
        }
    }
    if (rename(temporary.c_str(), markerPath.c_str()) != 0) {
        unlink(temporary.c_str());
        throw std::runtime_error("cannot install FreeCAD runtime marker");
    }
}

}  // namespace

void materializeFreecadRuntimeDirectory(const std::string& filesDir)
{
    // python311.zip + freecad-runtime.zip 已由 setupFreecadEnv 复制到 filesDir/runtime。
    // 本函数不使用嵌入式 Python；QAbility 会等待其 Promise 成功后再允许 QPA 启动 Qt main。

    const std::string root = libraryRoot();
    const std::string runtimeDir = filesDir + "/runtime";
    const std::string home = filesDir + "/freecad-home";
    OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                 "materializeFreecadRuntime begin filesDir=%{public}s", filesDir.c_str());
    ensureDirectory(runtimeDir);
    ensureDirectory(runtimeDir + "/lib");
    ensureDirectory(runtimeDir + "/lib/python3.11");
    ensureDirectory(home);

    {
        const std::string zipPath = runtimeDir + "/freecad-runtime.zip";
        const std::string marker = home + "/.runtime-ready";
        const std::string identity = runtimeArchiveIdentity(zipPath);
        if (!runtimeMarkerMatches(marker, identity)) {
            unlink(marker.c_str());
            removeTree(home + "/Mod");
            removeTree(home + "/Ext");
            removeTree(home + "/share");
            removeTree(home + "/FlexiMind");
            if (!extractZipToDir(zipPath, home)) {
                throw std::runtime_error("cannot extract freecad runtime zip (C++/zlib)");
            }
            writeRuntimeMarker(marker, identity);
        }
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                 "materializeFreecadRuntime done root=%{public}s home=%{public}s",
                 root.c_str(), home.c_str());
}

void writeStartupScriptInto(const std::string& home)
{
    ensureDirectory(home);
    const std::string script = home + "/harmonyos_startup.py";
    std::ofstream output(script, std::ios::trunc);
    if (!output || !(output <<
        "# Generated by FreeCAD HarmonyOS integration.\n"
        "try:\n"
        "    import FreeCAD\n"
        "    import FreeCADGui\n"
        "    general = FreeCAD.ParamGet('User parameter:BaseApp/Preferences/General')\n"
        "    autoload = general.GetString('AutoloadModule', '')\n"
        "    if autoload and autoload not in FreeCADGui.listWorkbenches():\n"
        "        general.SetString('AutoloadModule', '')\n"
        "except Exception as exc:\n"
        "    print('FreeCAD startup preference cleanup failed: %s' % exc)\n")) {
        throw std::runtime_error("cannot write FreeCAD GUI startup script");
    }
}

std::string writeGuiStartupScript(const std::string& filesDir)
{
    const std::string home = filesDir + "/freecad-home";
    writeStartupScriptInto(home);
    // QPA may hand FreeCAD the application-level path instead (see
    // applicationFilesDirectory()); QAbilityStage and QAbility race to publish
    // the argv. Install the same script under both roots so the file FreeCAD is
    // asked to run always exists.
    const std::string appFiles = applicationFilesDirectory(filesDir);
    if (appFiles != filesDir) {
        writeStartupScriptInto(appFiles + "/freecad-home");
    }
    return home + "/harmonyos_startup.py";
}

struct JobWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    NativeResourceManager* resourceManager = nullptr;
    std::string filesDir;
    std::string requestJson;
    std::string result;
    std::string error;
};

void setPythonArgv(const std::vector<std::string>& arguments)
{
    PyObject* sysModule = PyImport_ImportModule("sys");
    if (sysModule == nullptr) {
        throw std::runtime_error("cannot import Python sys module");
    }
    PyObject* argv = PyList_New(static_cast<Py_ssize_t>(arguments.size()));
    if (argv == nullptr) {
        Py_DECREF(sysModule);
        throw std::runtime_error("cannot allocate Python argv");
    }
    for (size_t index = 0; index < arguments.size(); ++index) {
        PyObject* value = PyUnicode_FromString(arguments[index].c_str());
        if (value == nullptr || PyList_SetItem(argv, static_cast<Py_ssize_t>(index), value) != 0) {
            Py_XDECREF(value);
            Py_DECREF(argv);
            Py_DECREF(sysModule);
            PyErr_Clear();
            throw std::runtime_error("cannot populate Python argv");
        }
    }
    if (PyObject_SetAttrString(sysModule, "argv", argv) != 0) {
        Py_DECREF(argv);
        Py_DECREF(sysModule);
        PyErr_Clear();
        throw std::runtime_error("cannot set Python argv");
    }
    Py_DECREF(argv);
    Py_DECREF(sysModule);
}

void appendRuntimePythonPath(const std::string& path)
{
    PyObject* sysModule = PyImport_ImportModule("sys");
    if (sysModule == nullptr) {
        throw std::runtime_error("cannot import Python sys module");
    }
    PyObject* paths = PyObject_GetAttrString(sysModule, "path");
    PyObject* value = PyUnicode_FromString(path.c_str());
    if (paths == nullptr || value == nullptr || PyList_Insert(paths, 0, value) != 0) {
        Py_XDECREF(value);
        Py_XDECREF(paths);
        Py_DECREF(sysModule);
        PyErr_Clear();
        throw std::runtime_error("cannot append FreeCAD runtime Python path");
    }
    Py_DECREF(value);
    Py_DECREF(paths);
    Py_DECREF(sysModule);
}

std::string runPythonJob(const std::string& root, const std::string& runtimeDir,
                         const std::string& outputDir, const WritableRuntimePaths& paths,
                         const std::string& requestJson)
{
    std::lock_guard<std::mutex> guard(pythonMutex);
    const std::string home = paths.home;
    const std::string jobsDir = home + "/jobs";
    ensureDirectory(jobsDir);
    const std::string requestPath = jobsDir + "/harmony-job.request.json";
    const std::string resultPath = jobsDir + "/harmony-job.result.json";
    const std::string scriptPath = home + "/FlexiMind/fleximind_job_runner.py";
    {
        std::ofstream request(requestPath, std::ios::trunc);
        if (!request || !(request << requestJson)) {
            throw std::runtime_error("cannot write FlexiMind job request");
        }
    }
    unlink(resultPath.c_str());
    if (access(scriptPath.c_str(), R_OK) != 0) {
        throw std::runtime_error("FlexiMind job runner is missing from the staged runtime");
    }

    setenv("FREECAD_PROBE_OUTPUT_DIR", jobsDir.c_str(), 1);
    setenv("FREECAD_PROBE_ROOT", root.c_str(), 1);
    const bool firstRun = !pythonInitialized.load(std::memory_order_acquire);
    if (firstRun) {
        initializePython(root, runtimeDir);
    }

    PyGILState_STATE gilState {};
    if (!firstRun) {
        gilState = PyGILState_Ensure();
    }
    try {
        // The runner lives under freecad-home/FlexiMind, while caller inputs
        // and job outputs belong to the app's filesDir sandbox.
        setenv("FLEXIMIND_FILES_DIR", outputDir.c_str(), 1);
        syncPythonEnvironment(root, jobsDir, paths);
        appendRuntimePythonPath(home);
        setPythonArgv({scriptPath, "--pass", requestPath, resultPath});
    }
    catch (...) {
        if (firstRun) {
            PyEval_SaveThread();
        }
        else {
            PyGILState_Release(gilState);
        }
        throw;
    }

    FILE* script = fopen(scriptPath.c_str(), "r");
    if (script == nullptr) {
        if (firstRun) {
            PyEval_SaveThread();
        }
        else {
            PyGILState_Release(gilState);
        }
        throw std::runtime_error("cannot open FlexiMind job runner: " + scriptPath);
    }
    PyObject* mainModule = PyImport_AddModule("__main__");
    PyObject* mainGlobals = mainModule == nullptr ? nullptr : PyModule_GetDict(mainModule);
    PyObject* execution = mainGlobals == nullptr
                              ? nullptr
                              : PyRun_FileExFlags(script, scriptPath.c_str(), Py_file_input,
                                                  mainGlobals, mainGlobals, 1, nullptr);
    const int runStatus = execution == nullptr ? -1 : 0;
    Py_XDECREF(execution);
    const std::string pythonError = fetchPythonError();
    if (firstRun) {
        PyEval_SaveThread();
    }
    else {
        PyGILState_Release(gilState);
    }

    if (access(resultPath.c_str(), R_OK) != 0) {
        throw std::runtime_error(pythonError.empty()
                                     ? "FlexiMind job failed without a result file"
                                     : "FlexiMind job failed: " + pythonError);
    }
    const std::string result = readFile(resultPath);
    if (runStatus != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, PROBE_LOG_DOMAIN, PROBE_LOG_TAG,
                     "FlexiMind job Python status=%{public}d detail=%{public}s",
                     runStatus, pythonError.c_str());
    }
    return result;
}

void executeJob(napi_env, void* data)
{
    auto* job = static_cast<JobWork*>(data);
    std::lock_guard<std::mutex> runtimeGuard(runtimeMutex);
    try {
        requireDirectory(job->filesDir);
        const WritableRuntimePaths paths = configureWritableRuntime(job->filesDir);
        const std::string root = libraryRoot();
        AcceptanceWork runtimeWork;
        runtimeWork.resourceManager = job->resourceManager;
        runtimeWork.outputDir = job->filesDir;
        const std::string runtimeDir = materializeRuntime(runtimeWork);
        materializeFreecadRuntimeDirectory(job->filesDir);
        job->result = runPythonJob(root, runtimeDir, job->filesDir, paths, job->requestJson);
    }
    catch (const std::exception& error) {
        job->error = error.what();
    }
}

void completeJob(napi_env env, napi_status status, void* data)
{
    auto* job = static_cast<JobWork*>(data);
    if (status != napi_ok && job->error.empty()) {
        job->error = "NAPI async FreeCAD job was cancelled";
    }
    if (job->error.empty()) {
        napi_value result;
        napi_create_string_utf8(env, job->result.c_str(), job->result.size(), &result);
        napi_resolve_deferred(env, job->deferred, result);
    }
    else {
        napi_value message;
        napi_value error;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, job->deferred, error);
    }
    OH_ResourceManager_ReleaseNativeResourceManager(job->resourceManager);
    napi_delete_async_work(env, job->work);
    delete job;
}

napi_value runJob(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 3) {
        napi_throw_type_error(env, nullptr,
                              "runJob expects filesDir, request JSON, and resource manager");
        return nullptr;
    }
    size_t filesLength = 0;
    size_t requestLength = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &filesLength) != napi_ok ||
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &requestLength) != napi_ok) {
        napi_throw_type_error(env, nullptr, "runJob filesDir and request JSON must be strings");
        return nullptr;
    }
    auto* job = new JobWork();
    job->filesDir.resize(filesLength + 1);
    job->requestJson.resize(requestLength + 1);
    size_t copiedFiles = 0;
    size_t copiedRequest = 0;
    if (napi_get_value_string_utf8(env, args[0], job->filesDir.data(), job->filesDir.size(), &copiedFiles) != napi_ok ||
        napi_get_value_string_utf8(env, args[1], job->requestJson.data(), job->requestJson.size(), &copiedRequest) != napi_ok) {
        delete job;
        napi_throw_type_error(env, nullptr, "cannot read runJob arguments");
        return nullptr;
    }
    job->filesDir.resize(copiedFiles);
    job->requestJson.resize(copiedRequest);
    job->resourceManager = OH_ResourceManager_InitNativeResourceManager(env, args[2]);
    if (job->resourceManager == nullptr) {
        delete job;
        napi_throw_type_error(env, nullptr, "cannot initialize the native resource manager");
        return nullptr;
    }
    napi_value promise;
    napi_create_promise(env, &job->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "FreeCADFlexiMindJob", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, executeJob, completeJob,
                               job, &job->work) != napi_ok ||
        napi_queue_async_work(env, job->work) != napi_ok) {
        OH_ResourceManager_ReleaseNativeResourceManager(job->resourceManager);
        if (job->work != nullptr) {
            napi_delete_async_work(env, job->work);
        }
        delete job;
        napi_throw_error(env, nullptr, "cannot queue FreeCAD job");
        return nullptr;
    }
    return promise;
}

bool getFilesDirArgument(napi_env env, napi_callback_info info, std::string& filesDir,
                         const char* functionName)
{
    size_t argc = 1;
    napi_value args[1] {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 1) {
        const std::string message = std::string(functionName) + " expects filesDir";
        napi_throw_type_error(env, nullptr, message.c_str());
        return false;
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "files directory must be a string");
        return false;
    }
    filesDir.resize(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, args[0], filesDir.data(), filesDir.size(), &copied) != napi_ok) {
        napi_throw_type_error(env, nullptr, "cannot read files directory");
        return false;
    }
    filesDir.resize(copied);
    return true;
}

napi_value materializeFreecadRuntime(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> runtimeGuard(runtimeMutex);
    std::string filesDir;
    if (!getFilesDirArgument(env, info, filesDir, "materializeFreecadRuntime")) {
        return nullptr;
    }

    try {
        materializeFreecadRuntimeDirectory(filesDir);
        return nullptr;
    }
    catch (const std::exception& error) {
        napi_throw_error(env, nullptr, error.what());
        return nullptr;
    }
}

struct RuntimeMaterializeWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string filesDir;
    std::string error;
};

void executeRuntimeMaterialize(napi_env, void* data)
{
    auto* runtime = static_cast<RuntimeMaterializeWork*>(data);
    std::lock_guard<std::mutex> runtimeGuard(runtimeMutex);
    try {
        materializeFreecadRuntimeDirectory(runtime->filesDir);
    }
    catch (const std::exception& error) {
        runtime->error = error.what();
    }
}

void completeRuntimeMaterialize(napi_env env, napi_status status, void* data)
{
    auto* runtime = static_cast<RuntimeMaterializeWork*>(data);
    if (status != napi_ok && runtime->error.empty()) {
        runtime->error = "native runtime materialization was cancelled";
    }

    if (runtime->error.empty()) {
        napi_value result;
        napi_get_undefined(env, &result);
        napi_resolve_deferred(env, runtime->deferred, result);
    }
    else {
        napi_value message;
        napi_value error;
        napi_create_string_utf8(env, runtime->error.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, runtime->deferred, error);
    }

    napi_delete_async_work(env, runtime->work);
    delete runtime;
}

napi_value materializeFreecadRuntimeAsync(napi_env env, napi_callback_info info)
{
    std::string filesDir;
    if (!getFilesDirArgument(env, info, filesDir, "materializeFreecadRuntimeAsync")) {
        return nullptr;
    }

    auto* runtime = new RuntimeMaterializeWork();
    runtime->filesDir = std::move(filesDir);

    napi_value promise;
    if (napi_create_promise(env, &runtime->deferred, &promise) != napi_ok) {
        delete runtime;
        napi_throw_error(env, nullptr, "cannot create runtime materialization Promise");
        return nullptr;
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "FreeCADRuntimeMaterialize", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, executeRuntimeMaterialize,
                               completeRuntimeMaterialize, runtime, &runtime->work) != napi_ok) {
        delete runtime;
        napi_throw_error(env, nullptr, "cannot create runtime materialization work");
        return nullptr;
    }
    if (napi_queue_async_work(env, runtime->work) != napi_ok) {
        napi_delete_async_work(env, runtime->work);
        delete runtime;
        napi_throw_error(env, nullptr, "cannot queue runtime materialization work");
        return nullptr;
    }
    return promise;
}

napi_value init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"runAcceptance", nullptr, runAcceptance, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runJob", nullptr, runJob, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"materializeFreecadRuntime", nullptr, materializeFreecadRuntime, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"materializeFreecadRuntimeAsync", nullptr, materializeFreecadRuntimeAsync, nullptr, nullptr,
         nullptr, napi_default, nullptr},
        {"prepareOpenGL", nullptr, prepareOpenGL, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setupFreecadEnv", nullptr, setupFreecadEnv, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

} // namespace

static napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = init,
    .nm_modname = "freecadacceptance",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void registerFreecadAcceptanceModule()
{
    // This constructor runs when ArkTS imports the NAPI module, before the
    // QPA setup callback.  Set the wrapper mode at the earliest possible
    // point; prepareOpenGL() later performs the path-dependent gl4es load.
    setenv("NEED_OPENGL", "1", 1);
    setenv("LIBGL_NOTEST", "1", 1);
    napi_module_register(&module);
}
