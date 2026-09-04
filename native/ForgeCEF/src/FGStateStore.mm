#import "FGStateStore.h"

@implementation FGStateStore {
  NSMutableDictionary<NSString *, id>* _values;
  NSLock* _lock;
  FGCommandHandler _commandHandler;
}

+ (FGStateStore *)shared {
  static FGStateStore* instance = nil;
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    instance = [[FGStateStore alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _values = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (void)setValue:(id)value forStateKey:(NSString *)key {
  [_lock lock];
  if (value) {
    _values[key] = value;
  } else {
    [_values removeObjectForKey:key];
  }
  [_lock unlock];
}

- (id)valueForStateKey:(NSString *)key {
  [_lock lock];
  id value = _values[key];
  [_lock unlock];
  return value;
}

- (NSDictionary<NSString *, id> *)snapshot {
  [_lock lock];
  NSDictionary* copy = [_values copy];
  [_lock unlock];
  return copy;
}

- (void)setCommandHandler:(FGCommandHandler)handler {
  [_lock lock];
  _commandHandler = [handler copy];
  [_lock unlock];
}

- (NSDictionary<NSString *, id> *)dispatchAction:(NSString *)action
                                         payload:(NSDictionary<NSString *, id> *)payload {
  [_lock lock];
  FGCommandHandler handler = _commandHandler;
  [_lock unlock];
  if (!handler) {
    return @{@"ok" : @NO, @"error" : @"no command handler registered"};
  }
  NSDictionary* result = handler(action, payload ?: @{});
  return result ?: @{@"ok" : @YES};
}

@end
