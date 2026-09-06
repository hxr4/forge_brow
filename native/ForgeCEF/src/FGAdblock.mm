#import "FGAdblock.h"
#import "FGAdblockInternal.h"

#include <atomic>
#include <string>
#include <string.h>
#include <vector>

#include "forge_adblock.h"

namespace {

std::atomic<uint64_t> gBlockedCount{0};
std::atomic<uint64_t> gEstimatedBytes{0};
std::atomic<uint64_t> gRequestsSeen{0};
NSMutableSet<NSString *>* gBlockedHosts = nil;
std::mutex gBlockedHostsLock;

NSString* HostFromURL(const char* url) {
  if (!url) {
    return nil;
  }
  NSString* text = [NSString stringWithUTF8String:url];
  if (text.length == 0) {
    return nil;
  }
  NSURLComponents* parts = [NSURLComponents componentsWithString:text];
  NSString* host = parts.host.lowercaseString;
  if (host.length == 0) {
    return nil;
  }
  return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
}
std::atomic<uint64_t> gBlockedScripts{0};
std::atomic<uint64_t> gBlockedBeacons{0};
std::atomic<uint64_t> gBlockedImages{0};
std::atomic<uint64_t> gBlockedFrames{0};
std::atomic<uint64_t> gBlockedOther{0};
std::atomic<uint64_t> gBlockedPopups{0};

uint64_t EstimatedSizeForType(const char* request_type) {
  if (!request_type) {
    return 15000;
  }
  if (strcmp(request_type, "script") == 0) {
    return 45000;
  }
  if (strcmp(request_type, "subdocument") == 0) {
    return 60000;
  }
  if (strcmp(request_type, "image") == 0) {
    return 25000;
  }
  if (strcmp(request_type, "stylesheet") == 0) {
    return 12000;
  }
  if (strcmp(request_type, "media") == 0) {
    return 150000;
  }
  if (strcmp(request_type, "xmlhttprequest") == 0 || strcmp(request_type, "fetch") == 0) {
    return 6000;
  }
  if (strcmp(request_type, "ping") == 0 || strcmp(request_type, "beacon") == 0) {
    return 800;
  }
  if (strcmp(request_type, "font") == 0) {
    return 40000;
  }
  return 15000;
}

}  // namespace

@implementation FGAdblock {
  ForgeAdblockEngine* _engine;
  NSString* _lastError;
  NSUInteger _listCount;
  NSUInteger _resourceCount;
}

+ (FGAdblock *)shared {
  static FGAdblock* instance = nil;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    instance = [[FGAdblock alloc] init];
  });
  return instance;
}

- (void)dealloc {
  if (_engine) {
    forge_adblock_free(_engine);
    _engine = nullptr;
  }
}

- (BOOL)loadFilterListsAtPaths:(NSArray<NSString *> *)paths {
  if (paths.count == 0) {
    _lastError = @"no filter lists configured";
    return NO;
  }

  std::vector<std::string> storage;
  storage.reserve(paths.count);
  for (NSString* path in paths) {
    storage.emplace_back(path.fileSystemRepresentation);
  }

  std::vector<const char*> pointers;
  pointers.reserve(storage.size());
  for (const auto& entry : storage) {
    pointers.push_back(entry.c_str());
  }

  ForgeAdblockEngine* engine = forge_adblock_new(pointers.data(), pointers.size());
  if (!engine) {
    const char* error = forge_adblock_last_error();
    _lastError = error ? @(error) : @"failed to build the blocking engine";
    return NO;
  }

  if (_engine) {
    forge_adblock_free(_engine);
  }
  _engine = engine;
  _lastError = nil;
  _listCount = paths.count;

  NSString* resources = [NSBundle.mainBundle pathForResource:@"resources" ofType:@"json" inDirectory:@"filters"];
  if (resources) {
    _resourceCount = forge_adblock_load_resources(_engine, resources.fileSystemRepresentation);
    NSLog(@"[forge] scriptlet resources loaded: %lu", (unsigned long)_resourceCount);
  } else {
    NSLog(@"[forge] scriptlet resources not found in bundle");
  }
  return YES;
}

- (BOOL)isReady {
  return _engine != nullptr;
}

- (NSUInteger)ruleCount {
  return _engine ? forge_adblock_rule_count(_engine) : 0;
}

- (NSUInteger)blockedCount {
  return static_cast<NSUInteger>(gBlockedCount.load(std::memory_order_relaxed));
}

- (NSUInteger)blockedPopupCount {
  return static_cast<NSUInteger>(gBlockedPopups.load(std::memory_order_relaxed));
}

- (void)noteBlockedPopup {
  gBlockedPopups.fetch_add(1, std::memory_order_relaxed);
}

- (NSUInteger)listCount {
  return _listCount;
}

- (NSUInteger)resourceCount {
  return _resourceCount;
}

- (NSString *)cosmeticJSONForURL:(const char *)url {
  if (!_engine || !url) {
    return nil;
  }
  char* raw = forge_adblock_cosmetic(_engine, url);
  if (!raw) {
    return nil;
  }
  NSString* result = @(raw);
  forge_adblock_string_free(raw);
  return result;
}

- (NSUInteger)estimatedBytesSaved {
  return static_cast<NSUInteger>(gEstimatedBytes.load(std::memory_order_relaxed));
}

- (NSString *)lastError {
  return _lastError;
}

- (void)resetCounters {
  gBlockedCount.store(0, std::memory_order_relaxed);
  gEstimatedBytes.store(0, std::memory_order_relaxed);
  gRequestsSeen.store(0, std::memory_order_relaxed);
  gBlockedScripts.store(0, std::memory_order_relaxed);
  gBlockedBeacons.store(0, std::memory_order_relaxed);
  gBlockedImages.store(0, std::memory_order_relaxed);
  gBlockedFrames.store(0, std::memory_order_relaxed);
  gBlockedOther.store(0, std::memory_order_relaxed);
}

- (BOOL)shouldBlockURL:(const char *)url
             sourceURL:(const char *)sourceURL
           requestType:(const char *)requestType {
  if (!_engine || !url) {
    return NO;
  }
  return forge_adblock_should_block(_engine, url, sourceURL ? sourceURL : "",
                                    requestType ? requestType : "other");
}

- (void)noteBlockedRequestOfType:(const char *)requestType {
  gBlockedCount.fetch_add(1, std::memory_order_relaxed);
  gEstimatedBytes.fetch_add(EstimatedSizeForType(requestType), std::memory_order_relaxed);

  const std::string type = requestType ? requestType : "other";
  if (type == "script") {
    gBlockedScripts.fetch_add(1, std::memory_order_relaxed);
  } else if (type == "xmlhttprequest" || type == "ping" || type == "csp" || type == "beacon") {
    gBlockedBeacons.fetch_add(1, std::memory_order_relaxed);
  } else if (type == "image") {
    gBlockedImages.fetch_add(1, std::memory_order_relaxed);
  } else if (type == "subdocument" || type == "document") {
    gBlockedFrames.fetch_add(1, std::memory_order_relaxed);
  } else {
    gBlockedOther.fetch_add(1, std::memory_order_relaxed);
  }
}

- (void)setBlockedHosts:(NSArray<NSString *> *)hosts {
  std::lock_guard<std::mutex> guard(gBlockedHostsLock);
  gBlockedHosts = [NSMutableSet setWithArray:hosts ?: @[]];
}

- (NSArray<NSString *> *)blockedHosts {
  std::lock_guard<std::mutex> guard(gBlockedHostsLock);
  return gBlockedHosts.allObjects ?: @[];
}

- (BOOL)isURLHostBlocked:(const char *)url {
  NSString* host = HostFromURL(url);
  if (host.length == 0) {
    return NO;
  }
  std::lock_guard<std::mutex> guard(gBlockedHostsLock);
  if (gBlockedHosts.count == 0) {
    return NO;
  }
  if ([gBlockedHosts containsObject:host]) {
    return YES;
  }
  for (NSString* blocked in gBlockedHosts) {
    if ([host hasSuffix:[@"." stringByAppendingString:blocked]]) {
      return YES;
    }
  }
  return NO;
}

- (void)noteRequestSeen {
  gRequestsSeen.fetch_add(1, std::memory_order_relaxed);
}

- (NSUInteger)requestsSeen {
  return static_cast<NSUInteger>(gRequestsSeen.load(std::memory_order_relaxed));
}

- (NSDictionary<NSString *, NSNumber *> *)blockedByType {
  return @{
    @"scripts": @(gBlockedScripts.load(std::memory_order_relaxed)),
    @"beacons": @(gBlockedBeacons.load(std::memory_order_relaxed)),
    @"images": @(gBlockedImages.load(std::memory_order_relaxed)),
    @"frames": @(gBlockedFrames.load(std::memory_order_relaxed)),
    @"other": @(gBlockedOther.load(std::memory_order_relaxed))
  };
}

@end
