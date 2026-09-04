#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, FGBypassOptions) {
  FGBypassOptionsNone = 0,
  FGBypassOptionsCertificateErrors = 1 << 0,
};

typedef NS_ENUM(NSInteger, FGNavigationDisposition) {
  FGNavigationDispositionCurrentTab,
  FGNavigationDispositionNewForegroundTab,
  FGNavigationDispositionNewBackgroundTab,
};

NS_ASSUME_NONNULL_END
