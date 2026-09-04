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
}

@end
