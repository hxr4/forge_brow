#import "FGEngine.h"

#import "FGAdblock.h"
#import "FGSchemeHandler.h"

#include <string>

#include "include/cef_app.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_version.h"

#include "forge_schemes.h"

@implementation FGEngineConfiguration
@end

namespace {

class FGBrowserProcessApp : public CefApp, public CefBrowserProcessHandler {
 public:
  FGBrowserProcessApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    ForgeRegisterCustomSchemes(registrar);
  }

  void OnContextInitialized() override { FGRegisterSchemeHandlerFactory(); }

  FGBrowserProcessApp(const FGBrowserProcessApp&) = delete;
  FGBrowserProcessApp& operator=(const FGBrowserProcessApp&) = delete;

 private:
  IMPLEMENT_REFCOUNTING(FGBrowserProcessApp);
};

CefRefPtr<FGBrowserProcessApp> gApp;

std::string BundleSubpath(NSString* relative) {
  NSString* base = NSBundle.mainBundle.bundlePath;
  return [base stringByAppendingPathComponent:relative].fileSystemRepresentation;
}

}  // namespace

@implementation FGEngine

+ (BOOL)startWithConfiguration:(FGEngineConfiguration *)configuration
                          argc:(int)argc
                          argv:(char **)argv {
  FGSetWebResourceRoot(std::string(configuration.webResourcePath.fileSystemRepresentation));

  if (![FGAdblock.shared loadFilterListsAtPaths:configuration.filterListPaths]) {
    NSLog(@"[forge] blocking engine unavailable: %@", FGAdblock.shared.lastError);
  } else {
    NSLog(@"[forge] blocking engine ready with %lu rules",
          (unsigned long)FGAdblock.shared.ruleCount);
  }

  CefMainArgs main_args(argc, argv);
  gApp = new FGBrowserProcessApp();

  CefSettings settings;
  settings.no_sandbox = false;
  settings.external_message_pump = false;
  settings.multi_threaded_message_loop = false;
  settings.windowless_rendering_enabled = false;
  settings.log_severity = LOGSEVERITY_WARNING;

  CefString(&settings.cache_path) = configuration.cachePath.fileSystemRepresentation;
  CefString(&settings.root_cache_path) = configuration.cachePath.fileSystemRepresentation;
  CefString(&settings.main_bundle_path) = NSBundle.mainBundle.bundlePath.fileSystemRepresentation;
  CefString(&settings.framework_dir_path) =
      BundleSubpath(@"Contents/Frameworks/Chromium Embedded Framework.framework");
  CefString(&settings.browser_subprocess_path) =
      BundleSubpath(@"Contents/Frameworks/Forge Helper.app/Contents/MacOS/Forge Helper");

  if (!CefInitialize(main_args, settings, gApp.get(), nullptr)) {
    NSLog(@"[forge] CefInitialize failed");
    return NO;
  }
  return YES;
}

+ (void)runMessageLoop {
  CefRunMessageLoop();
}

+ (void)quitMessageLoop {
  CefQuitMessageLoop();
}

+ (void)shutdown {
  CefShutdown();
  gApp = nullptr;
}

+ (NSString *)cefVersion {
  return @(CEF_VERSION);
}

@end
