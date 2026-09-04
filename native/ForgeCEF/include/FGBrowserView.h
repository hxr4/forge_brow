#import <Cocoa/Cocoa.h>
#import "FGTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class FGBrowserView;

@protocol FGBrowserViewDelegate <NSObject>
@optional
- (void)browserView:(FGBrowserView *)view didChangeURL:(NSString *)url;
- (void)browserView:(FGBrowserView *)view didChangeTitle:(NSString *)title;
- (void)browserView:(FGBrowserView *)view didChangeFavicon:(nullable NSImage *)favicon;
- (void)browserView:(FGBrowserView *)view
    didChangeLoading:(BOOL)loading
           canGoBack:(BOOL)canGoBack
        canGoForward:(BOOL)canGoForward;
- (void)browserView:(FGBrowserView *)view didFailWithMessage:(NSString *)message url:(NSString *)url;
- (void)browserView:(FGBrowserView *)view
    didRequestNewTabWithURL:(NSString *)url
                disposition:(FGNavigationDisposition)disposition;
- (void)browserViewDidRequestCommandPalette:(FGBrowserView *)view;
- (void)browserViewDidUpdateBlockCount:(FGBrowserView *)view;
- (void)browserView:(FGBrowserView *)view
    didUpdateFindMatchCount:(NSInteger)count
                     active:(NSInteger)activeOrdinal;
@end

@interface FGBrowserView : NSView

@property (nonatomic, weak, nullable) id<FGBrowserViewDelegate> browserDelegate;

@property (nonatomic, readonly, copy) NSString *currentURL;
@property (nonatomic, readonly, copy) NSString *currentTitle;
@property (nonatomic, readonly, nullable) NSImage *favicon;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) NSUInteger blockedCountForTab;
@property (nonatomic, readonly) NSUInteger cosmeticSelectorCount;

@property (nonatomic, assign) FGBypassOptions bypassOptions;

- (instancetype)initWithFrame:(NSRect)frame initialURL:(NSString *)url;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoading;
- (void)showDevTools;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;
- (NSInteger)zoomPercent;
- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding:(BOOL)clearSelection;
- (void)viewSource;
- (void)editUndo;
- (void)editRedo;
- (void)editCut;
- (void)editCopy;
- (void)editPaste;
- (void)editSelectAll;
- (void)printPage;
- (void)closeBrowser;
- (void)executeJavaScript:(NSString *)script;
- (void)evaluate:(NSString *)expression completion:(void (^)(id _Nullable result))completion;

@end

NS_ASSUME_NONNULL_END
