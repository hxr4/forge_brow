#import "FGDownloads.h"

@implementation FGDownloads {
  NSMutableArray<NSMutableDictionary<NSString *, id> *>* _items;
  NSLock* _lock;
}

+ (FGDownloads *)shared {
  static FGDownloads* instance = nil;
  static dispatch_once_t token;
  dispatch_once(&token, ^{ instance = [[FGDownloads alloc] init]; });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _items = [NSMutableArray array];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (void)updateWithIdentifier:(uint32_t)identifier
                        name:(NSString *)name
                        path:(NSString *)path
                         url:(NSString *)url
                     percent:(int)percent
                    received:(int64_t)received
                       total:(int64_t)total
                    complete:(BOOL)complete
                   cancelled:(BOOL)cancelled {
  [_lock lock];
  NSMutableDictionary* found = nil;
  for (NSMutableDictionary* entry in _items) {
    if ([entry[@"id"] unsignedIntValue] == identifier) { found = entry; break; }
  }
  if (!found) {
    found = [NSMutableDictionary dictionary];
    found[@"id"] = @(identifier);
    found[@"startedAt"] = @([NSDate date].timeIntervalSince1970);
    [_items insertObject:found atIndex:0];
    if (_items.count > 60) [_items removeLastObject];
  }
  found[@"name"] = name ?: @"";
  found[@"path"] = path ?: @"";
  found[@"url"] = url ?: @"";
  found[@"percent"] = @(percent);
  found[@"received"] = @(received);
  found[@"total"] = @(total);
  found[@"complete"] = @(complete);
  found[@"cancelled"] = @(cancelled);
  [_lock unlock];
}

- (NSArray<NSDictionary<NSString *, id> *> *)snapshot {
  [_lock lock];
  NSArray* copy = [[NSArray alloc] initWithArray:_items copyItems:YES];
  [_lock unlock];
  return copy;
}

- (void)clearCompleted {
  [_lock lock];
  NSPredicate* keep = [NSPredicate predicateWithBlock:^BOOL(id entry, NSDictionary* b) {
    return ![entry[@"complete"] boolValue];
  }];
  [_items filterUsingPredicate:keep];
  [_lock unlock];
}

@end
