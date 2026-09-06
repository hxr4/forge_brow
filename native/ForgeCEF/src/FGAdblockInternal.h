#import "FGAdblock.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGAdblock (Internal)

- (BOOL)shouldBlockURL:(const char *)url
             sourceURL:(const char *)sourceURL
          requestType:(const char *)requestType;

- (void)noteBlockedRequestOfType:(const char *)requestType;
- (void)noteRequestSeen;
- (BOOL)isURLHostBlocked:(const char *)url;

- (nullable NSString *)cosmeticJSONForURL:(const char *)url;

- (void)noteBlockedPopup;

@end

NS_ASSUME_NONNULL_END
