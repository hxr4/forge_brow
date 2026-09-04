#import <Cocoa/Cocoa.h>

#import "ForgeCEF.h"

#include "include/wrapper/cef_library_loader.h"

static id gAppDelegate = nil;

static NSString* ProfileDirectory() {
  NSArray<NSString*>* paths =
      NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
  NSString* base = paths.firstObject ?: NSTemporaryDirectory();
  NSString* directory =
      [[base stringByAppendingPathComponent:@"Forge Browser"] stringByAppendingPathComponent:@"profiles/default"];
  [NSFileManager.defaultManager createDirectoryAtPath:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  return directory;
}

static NSArray<NSString*>* FilterListPaths() {
  NSArray<NSString*>* found = [NSBundle.mainBundle pathsForResourcesOfType:@"txt" inDirectory:@"filters"];
  return [found sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

int main(int argc, char* argv[]) {
  @autoreleasepool {
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain()) {
      NSLog(@"[forge] failed to load the CEF framework");
      return 1;
    }

    [NSClassFromString(@"FGApplication") sharedApplication];

    FGEngineConfiguration* configuration = [[FGEngineConfiguration alloc] init];
    configuration.cachePath = ProfileDirectory();
    configuration.filterListPaths = FilterListPaths();
    configuration.webResourcePath =
        [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"web"];

    if (![FGEngine startWithConfiguration:configuration argc:argc argv:argv]) {
      return 1;
    }

    Class delegateClass = NSClassFromString(@"ForgeAppDelegate");
    if (!delegateClass) {
      NSLog(@"[forge] ForgeAppDelegate not found");
      return 1;
    }
    gAppDelegate = [[delegateClass alloc] init];
    NSApp.delegate = gAppDelegate;

    [FGEngine runMessageLoop];
    [FGEngine shutdown];
  }
  return 0;
}
