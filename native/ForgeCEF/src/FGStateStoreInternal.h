#import "FGStateStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGStateStore (Internal)
- (NSDictionary<NSString *, id> *)dispatchAction:(NSString *)action
                                         payload:(NSDictionary<NSString *, id> *)payload;
@end

NS_ASSUME_NONNULL_END
