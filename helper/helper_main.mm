#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

#include "forge_schemes.h"

namespace {

class ForgeHelperApp : public CefApp {
 public:
  ForgeHelperApp() = default;

  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    ForgeRegisterCustomSchemes(registrar);
  }

  ForgeHelperApp(const ForgeHelperApp&) = delete;
  ForgeHelperApp& operator=(const ForgeHelperApp&) = delete;

 private:
  IMPLEMENT_REFCOUNTING(ForgeHelperApp);
};

}  // namespace

int main(int argc, char* argv[]) {
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }

  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  CefRefPtr<CefApp> app(new ForgeHelperApp);
  return CefExecuteProcess(main_args, app, nullptr);
}
