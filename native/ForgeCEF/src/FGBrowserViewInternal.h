#import "FGBrowserView.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGBrowserView (Internal)
- (void)handleAddressChange:(NSString *)url;
- (void)handleTitleChange:(NSString *)title;
- (void)handleLoadingState:(BOOL)loading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)handleLoadError:(NSString *)message url:(NSString *)url;
- (void)handleBrowserCreated;
- (void)handleBrowserClosed;
- (void)handleCommandPaletteShortcut;
- (void)handleBlockedRequest;
- (void)handleFindMatchCount:(NSInteger)count active:(NSInteger)activeOrdinal;
- (void)handleNewTabRequest:(NSString *)url disposition:(FGNavigationDisposition)disposition;
@end

NS_ASSUME_NONNULL_END
