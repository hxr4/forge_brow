#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGEngineConfiguration : NSObject
@property (nonatomic, copy) NSString *cachePath;
@property (nonatomic, copy) NSArray<NSString *> *filterListPaths;
@property (nonatomic, copy) NSString *webResourcePath;
@end

@interface FGEngine : NSObject

+ (BOOL)startWithConfiguration:(FGEngineConfiguration *)configuration argc:(int)argc argv:(char **)argv;
+ (void)runMessageLoop;
+ (void)quitMessageLoop;
+ (void)shutdown;
+ (NSString *)cefVersion;
+ (uint64_t)memoryFootprint;
+ (NSUInteger)helperProcessCount;

@end

NS_ASSUME_NONNULL_END
