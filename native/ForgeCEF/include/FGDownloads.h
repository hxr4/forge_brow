#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGDownloads : NSObject

@property (class, nonatomic, readonly) FGDownloads *shared;

- (void)updateWithIdentifier:(uint32_t)identifier
                        name:(NSString *)name
                        path:(NSString *)path
                         url:(NSString *)url
                     percent:(int)percent
                    received:(int64_t)received
                       total:(int64_t)total
                    complete:(BOOL)complete
                   cancelled:(BOOL)cancelled;

- (NSArray<NSDictionary<NSString *, id> *> *)snapshot;
- (void)clearCompleted;

@end

NS_ASSUME_NONNULL_END
