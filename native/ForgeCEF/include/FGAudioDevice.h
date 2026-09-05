#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGAudioDevice : NSObject

+ (NSDictionary<NSString *, id> *)currentOutput;

@end

NS_ASSUME_NONNULL_END
