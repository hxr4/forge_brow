#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> *_Nullable (^FGCommandHandler)(NSString *action,
                                                                   NSDictionary<NSString *, id> *payload);

@interface FGStateStore : NSObject

@property (class, nonatomic, readonly) FGStateStore *shared;

- (void)setValue:(nullable id)value forStateKey:(NSString *)key;
- (nullable id)valueForStateKey:(NSString *)key;
- (NSDictionary<NSString *, id> *)snapshot;

- (void)setCommandHandler:(nullable FGCommandHandler)handler;

@end

NS_ASSUME_NONNULL_END
