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
/// Right-click inside the page. |params| carries the CEF context menu state
/// (link, image, media, selection, edit flags, coordinates in view points).
- (void)browserView:(FGBrowserView *)view
    requestsContextMenuWithParams:(NSDictionary<NSString *, id> *)params;
/// The page entered or left HTML5 fullscreen (video players, games).
- (void)browserView:(FGBrowserView *)view didChangeContentFullscreen:(BOOL)fullscreen;
- (void)browserView:(FGBrowserView *)view didChangeLoadProgress:(double)progress;
- (void)browserView:(FGBrowserView *)view didChangeStatusText:(NSString *)text;
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
@property (nonatomic, readonly) NSDictionary<NSString *, id> *mediaProperties;
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, id> *> *recentRequests;

@property (nonatomic, assign) FGBypassOptions bypassOptions;

- (instancetype)initWithFrame:(NSRect)frame initialURL:(NSString *)url;
- (instancetype)initWithFrame:(NSRect)frame
                   initialURL:(NSString *)url
              privateBrowsing:(BOOL)privateBrowsing;
@property (nonatomic, readonly) BOOL privateBrowsing;

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
- (void)editPasteAndMatchStyle;
- (void)editDelete;
- (void)setAudioMuted:(BOOL)muted;
@property (nonatomic, readonly) BOOL isContentFullscreen;
- (void)exitContentFullscreen;
- (void)startDownload:(NSString *)url;
- (void)downloadImage:(NSString *)url completion:(void (^)(NSImage * _Nullable image))completion;
/// Opens DevTools with the element under |point| (view points, top-left origin) selected.
- (void)showDevToolsInspectingPoint:(NSPoint)point;
@property (nonatomic, readonly) BOOL isAudioMuted;
- (void)closeBrowser;
- (void)executeJavaScript:(NSString *)script;
- (void)evaluate:(NSString *)expression completion:(void (^)(id _Nullable result))completion;
/// Same as evaluate:, but the page sees it as a user gesture. Only for actions
/// the user explicitly picked (picture-in-picture, fullscreen).
- (void)evaluateUserAction:(NSString *)expression completion:(nullable void (^)(id _Nullable result))completion;
- (void)replaceMisspelling:(NSString *)word;

@property (class, nonatomic, copy, nullable) NSString *documentStartScript;

@end

NS_ASSUME_NONNULL_END
