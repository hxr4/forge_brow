#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGAdblock : NSObject

@property (class, nonatomic, readonly) FGAdblock *shared;

@property (nonatomic, readonly, getter=isReady) BOOL ready;
@property (nonatomic, readonly) NSUInteger ruleCount;
@property (nonatomic, readonly) NSUInteger blockedCount;
@property (nonatomic, readonly) NSUInteger blockedPopupCount;
@property (nonatomic, readonly) NSUInteger listCount;
@property (nonatomic, readonly) NSUInteger resourceCount;
@property (nonatomic, readonly) NSUInteger estimatedBytesSaved;
@property (nonatomic, readonly) NSUInteger requestsSeen;
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *blockedByType;
@property (nonatomic, readonly, nullable) NSString *lastError;

- (BOOL)loadFilterListsAtPaths:(NSArray<NSString *> *)paths;
- (void)noteRequestSeen;
- (void)resetCounters;

@end

NS_ASSUME_NONNULL_END
