#import "FGEngine.h"

#import <mach/mach.h>
#import <libproc.h>

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

+ (uint64_t)memoryFootprint {
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
    return 0;
  }
  return info.phys_footprint;
}

+ (NSUInteger)helperProcessCount {
  const int reported = proc_listallpids(NULL, 0);
  if (reported <= 0) {
    return 0;
  }
  const int capacity = reported + 64;
  pid_t* pids = (pid_t*)calloc((size_t)capacity, sizeof(pid_t));
  if (!pids) {
    return 0;
  }

  const int bytes = proc_listallpids(pids, (int)(capacity * sizeof(pid_t)));
  const int found = bytes / (int)sizeof(pid_t);
  NSUInteger total = 0;
  char path[PROC_PIDPATHINFO_MAXSIZE];

  for (int index = 0; index < found; index++) {
    if (pids[index] <= 0) {
      continue;
    }
    if (proc_pidpath(pids[index], path, sizeof(path)) <= 0) {
      continue;
    }
    if (strstr(path, "Forge Helper") != NULL) {
      total += 1;
    }
  }

  free(pids);
  return total;
}


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
