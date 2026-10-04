#import "FGBrowserView.h"
#import "FGBrowserViewInternal.h"

#import "FGClient.h"

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_request_context.h"
#include "include/cef_image.h"
#include "include/cef_values.h"

#import "FGSchemeHandler.h"
#include "include/internal/cef_types_mac.h"

@interface FGBrowserView ()
- (void)createBrowser;
- (CefRefPtr<CefBrowser>)cefBrowser;
@end

@implementation FGBrowserView {
  CefRefPtr<FGClient> _client;
  NSString* _pendingURL;
  BOOL _browserRequested;
  NSString* _currentURL;
  NSString* _currentTitle;
  NSImage* _favicon;
  NSUInteger _cosmeticSelectorCount;
  NSMutableDictionary* _mediaProperties;
  NSString* _faviconHost;
  BOOL _isLoading;
  BOOL _canGoBack;
  BOOL _canGoForward;
  BOOL _contentFullscreen;
  NSUInteger _createAttempts;
}

static NSString* gDocumentStartScript = nil;

+ (NSString *)documentStartScript {
  return gDocumentStartScript;
}

+ (void)setDocumentStartScript:(NSString *)documentStartScript {
  gDocumentStartScript = [documentStartScript copy];
}

namespace {

class FGImageCallback : public CefDownloadImageCallback {
 public:
  explicit FGImageCallback(void (^completion)(NSImage*)) : completion_([completion copy]) {}

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    NSData* data = nil;
    if (image) {
      int width = 0;
      int height = 0;
      CefRefPtr<CefBinaryValue> png = image->GetAsPNG(1.0f, true, width, height);
      if (png && png->GetSize() > 0) {
        NSMutableData* bytes = [NSMutableData dataWithLength:png->GetSize()];
        if (png->GetData(bytes.mutableBytes, bytes.length, 0) == bytes.length) {
          data = bytes;
        }
      }
    }
    void (^completion)(NSImage*) = completion_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSImage* result = data ? [[NSImage alloc] initWithData:data] : nil;
      completion(result.isValid ? result : nil);
    });
  }

 private:
  void (^completion_)(NSImage*);
  IMPLEMENT_REFCOUNTING(FGImageCallback);
};

CefRefPtr<CefRequestContext> PrivateRequestContext() {
  static CefRefPtr<CefRequestContext> context;
  if (!context) {
    CefRequestContextSettings settings;
    context = CefRequestContext::CreateContext(settings, nullptr);
    FGRegisterSchemeHandlerFactoryOn(context);
  }
  return context;
}

}  // namespace

- (instancetype)initWithFrame:(NSRect)frame initialURL:(NSString *)url {
  return [self initWithFrame:frame initialURL:url privateBrowsing:NO];
}

- (instancetype)initWithFrame:(NSRect)frame
                   initialURL:(NSString *)url
              privateBrowsing:(BOOL)privateBrowsing {
  self = [super initWithFrame:frame];
  if (self) {
    _privateBrowsing = privateBrowsing;
    _pendingURL = [url copy] ?: @"about:blank";
    _currentURL = _pendingURL;
    _currentTitle = @"";
    _bypassOptions = FGBypassOptionsNone;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
  }
  return self;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window && !_browserRequested) {
    _browserRequested = YES;
    [self createBrowser];
  }
}

- (void)createBrowser {
  _createAttempts += 1;
  _client = new FGClient(self);
  _client->SetIgnoreCertificateErrors((_bypassOptions & FGBypassOptionsCertificateErrors) != 0);

  CefWindowInfo window_info;
  const NSRect bounds = self.bounds;
  CefRect rect(0, 0, static_cast<int>(bounds.size.width),
               static_cast<int>(bounds.size.height));
  window_info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self), rect);

  CefBrowserSettings settings;
  settings.background_color = CefColorSetARGB(255, 0, 0, 0);

  CefRefPtr<CefRequestContext> context =
      _privateBrowsing ? PrivateRequestContext() : nullptr;

  const bool created = CefBrowserHost::CreateBrowser(window_info, _client.get(),
                                                     CefString(_pendingURL.UTF8String), settings,
                                                     nullptr, context);

  // A tab whose browser never arrives is dead for good (reload is a no-op), so
  // retry a refused or lost creation a couple of times. A late arrival from an
  // abandoned attempt closes itself in FGClient::OnAfterCreated.
  CefRefPtr<FGClient> pending = _client;
  __weak FGBrowserView* weakSelf = self;
  const NSUInteger attempt = _createAttempts;
  const double delay = created ? 5.0 : 0.25;
  if (!created) {
    NSLog(@"[forge] CreateBrowser refused for %@ (attempt %lu)", _pendingURL, (unsigned long)attempt);
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    FGBrowserView* strong = weakSelf;
    if (!strong || attempt >= 3 || strong->_client.get() != pending.get() || pending->is_detached() ||
        pending->browser() || !strong.window) {
      return;
    }
    NSLog(@"[forge] browser for %@ never arrived; retrying", strong->_pendingURL);
    pending->Detach();
    [strong createBrowser];
  });
}

- (CefRefPtr<CefBrowser>)cefBrowser {
  if (!_client) {
    return nullptr;
  }
  return _client->browser();
}

- (void)layout {
  [super layout];
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return;
  }
  NSView* child = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
  if (child) {
    child.frame = self.bounds;
  }
}

- (void)setBypassOptions:(FGBypassOptions)bypassOptions {
  _bypassOptions = bypassOptions;
  if (_client) {
    _client->SetIgnoreCertificateErrors((bypassOptions & FGBypassOptionsCertificateErrors) != 0);
  }
}

- (NSString *)currentURL {
  return _currentURL ?: @"";
}

- (NSString *)currentTitle {
  return _currentTitle ?: @"";
}

- (NSImage *)favicon {
  return _favicon;
}

- (NSUInteger)cosmeticSelectorCount {
  return _cosmeticSelectorCount;
}

- (void)handleCosmeticSelectorCount:(NSUInteger)count {
  _cosmeticSelectorCount = count;
}

- (NSArray<NSDictionary<NSString *, id> *> *)recentRequests {
  if (!_client) {
    return @[];
  }
  return _client->CopyRequests();
}

- (NSDictionary<NSString *, id> *)mediaProperties {
  return _mediaProperties ?: @{};
}

- (void)mergeMediaProperties:(NSDictionary *)properties {
  if (!_mediaProperties) {
    _mediaProperties = [NSMutableDictionary dictionary];
  }
  [_mediaProperties addEntriesFromDictionary:properties];
}

- (BOOL)isLoading {
  return _isLoading;
}

- (BOOL)canGoBack {
  return _canGoBack;
}

- (BOOL)canGoForward {
  return _canGoForward;
}

- (NSUInteger)blockedCountForTab {
  if (!_client) {
    return 0;
  }
  return static_cast<NSUInteger>(_client->blocked_count());
}

- (void)loadURL:(NSString *)url {
  if (url.length == 0) {
    return;
  }
  _pendingURL = [url copy];
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return;
  }
  browser->GetMainFrame()->LoadURL(CefString(url.UTF8String));
}

- (void)goBack {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->GoBack();
  }
}

- (void)goForward {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->GoForward();
  }
}

- (void)reload {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->Reload();
  }
}

- (void)reloadIgnoringCache {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->ReloadIgnoreCache();
  }
}

- (void)stopLoading {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->StopLoad();
  }
}

- (void)showDevTools {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return;
  }
  CefWindowInfo window_info;
  CefBrowserSettings settings;
  browser->GetHost()->ShowDevTools(window_info, nullptr, settings, CefPoint());
}

- (void)zoomIn {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) return;
  double level = browser->GetHost()->GetZoomLevel();
  browser->GetHost()->SetZoomLevel(MIN(level + 0.5, 5.0));
}

- (void)zoomOut {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) return;
  double level = browser->GetHost()->GetZoomLevel();
  browser->GetHost()->SetZoomLevel(MAX(level - 0.5, -4.0));
}

- (void)resetZoom {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) browser->GetHost()->SetZoomLevel(0.0);
}

- (NSInteger)zoomPercent {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) return 100;
  return (NSInteger)llround(pow(1.2, browser->GetHost()->GetZoomLevel()) * 100.0);
}

- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser || text.length == 0) return;
  browser->GetHost()->Find(CefString(text.UTF8String), forward, matchCase, findNext);
}

- (void)stopFinding:(BOOL)clearSelection {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) browser->GetHost()->StopFinding(clearSelection);
}

- (void)viewSource {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) browser->GetMainFrame()->ViewSource();
}

- (void)editUndo { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Undo(); }
- (void)editRedo { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Redo(); }
- (void)editCut { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Cut(); }
- (void)editCopy { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Copy(); }
- (void)editPaste { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Paste(); }
- (void)editSelectAll { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->SelectAll(); }

- (void)editPasteAndMatchStyle { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->PasteAndMatchStyle(); }
- (void)editDelete { CefRefPtr<CefBrowser> b = [self cefBrowser]; if (b) b->GetFocusedFrame()->Delete(); }

- (BOOL)isContentFullscreen {
  return _contentFullscreen;
}

- (void)exitContentFullscreen {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser && browser->GetHost()->IsFullscreen()) {
    browser->GetHost()->ExitFullscreen(true);
  }
}

- (void)startDownload:(NSString *)url {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser && url.length > 0) {
    browser->GetHost()->StartDownload(CefString(url.UTF8String));
  }
}

- (void)downloadImage:(NSString *)url completion:(void (^)(NSImage *))completion {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser || url.length == 0) {
    if (completion) {
      completion(nil);
    }
    return;
  }
  browser->GetHost()->DownloadImage(CefString(url.UTF8String), false, 0, false,
                                    new FGImageCallback(completion ?: ^(NSImage*) {}));
}

- (void)showDevToolsInspectingPoint:(NSPoint)point {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return;
  }
  CefWindowInfo window_info;
  CefBrowserSettings settings;
  browser->GetHost()->ShowDevTools(window_info, nullptr, settings,
                                   CefPoint(static_cast<int>(point.x), static_cast<int>(point.y)));
}

- (void)setAudioMuted:(BOOL)muted {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->GetHost()->SetAudioMuted(muted ? true : false);
  }
}

- (BOOL)isAudioMuted {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return NO;
  }
  return browser->GetHost()->IsAudioMuted() ? YES : NO;
}

- (void)printPage {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) browser->GetHost()->Print();
}

- (void)handleFindMatchCount:(NSInteger)count active:(NSInteger)activeOrdinal {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didUpdateFindMatchCount:active:)]) {
    [delegate browserView:self didUpdateFindMatchCount:count active:activeOrdinal];
  }
}

- (void)executeJavaScript:(NSString *)script {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser || script.length == 0) {
    return;
  }
  browser->GetMainFrame()->ExecuteJavaScript(CefString(script.UTF8String),
                                             browser->GetMainFrame()->GetURL(), 0);
}

- (void)evaluate:(NSString *)expression completion:(void (^)(id))completion {
  if (!_client || expression.length == 0) {
    if (completion) {
      completion(nil);
    }
    return;
  }
  _client->Evaluate(std::string(expression.UTF8String), completion);
}

- (void)evaluateUserAction:(NSString *)expression completion:(void (^)(id))completion {
  if (!_client || expression.length == 0) {
    if (completion) {
      completion(nil);
    }
    return;
  }
  _client->Evaluate(std::string(expression.UTF8String), completion, true);
}

- (void)replaceMisspelling:(NSString *)word {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser && word.length > 0) {
    browser->GetHost()->ReplaceMisspelling(CefString(word.UTF8String));
  }
}

- (void)closeBrowser {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (browser) {
    browser->GetHost()->CloseBrowser(true);
  }
  if (_client) {
    _client->Detach();
  }
}

- (void)handleBrowserCreated {
  CefRefPtr<CefBrowser> browser = [self cefBrowser];
  if (!browser) {
    return;
  }
  NSView* child = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
  if (child) {
    child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    child.frame = self.bounds;
  }
}

- (void)handleBrowserClosed {
  _client = nullptr;
}

- (void)handleFaviconChange:(NSImage *)favicon {
  _favicon = favicon;
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeFavicon:)]) {
    [delegate browserView:self didChangeFavicon:favicon];
  }
}

- (void)handleAddressChange:(NSString *)url {
  NSString* host = [NSURL URLWithString:url].host ?: @"";
  if (_faviconHost && ![_faviconHost isEqualToString:host]) {
    [self handleFaviconChange:nil];
    [_mediaProperties removeAllObjects];
  }
  _faviconHost = [host copy];
  _currentURL = [url copy];
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeURL:)]) {
    [delegate browserView:self didChangeURL:_currentURL];
  }
}

- (void)handleTitleChange:(NSString *)title {
  _currentTitle = [title copy];
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeTitle:)]) {
    [delegate browserView:self didChangeTitle:_currentTitle];
  }
}

- (void)handleLoadingState:(BOOL)loading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward {
  _isLoading = loading;
  _canGoBack = canGoBack;
  _canGoForward = canGoForward;
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeLoading:canGoBack:canGoForward:)]) {
    [delegate browserView:self
        didChangeLoading:loading
               canGoBack:canGoBack
            canGoForward:canGoForward];
  }
}

- (void)handleLoadError:(NSString *)message url:(NSString *)url {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didFailWithMessage:url:)]) {
    [delegate browserView:self didFailWithMessage:message url:url];
  }
}

- (void)handleCommandPaletteShortcut {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserViewDidRequestCommandPalette:)]) {
    [delegate browserViewDidRequestCommandPalette:self];
  }
}

- (void)handleBlockedRequest {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserViewDidUpdateBlockCount:)]) {
    [delegate browserViewDidUpdateBlockCount:self];
  }
}

- (void)handleContextMenu:(NSDictionary *)params {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:requestsContextMenuWithParams:)]) {
    [delegate browserView:self requestsContextMenuWithParams:params];
  }
}

- (void)handleContentFullscreen:(BOOL)fullscreen {
  if (_contentFullscreen == fullscreen) {
    return;
  }
  _contentFullscreen = fullscreen;
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeContentFullscreen:)]) {
    [delegate browserView:self didChangeContentFullscreen:fullscreen];
  }
}

- (void)handleLoadProgress:(double)progress {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeLoadProgress:)]) {
    [delegate browserView:self didChangeLoadProgress:progress];
  }
}

- (void)handleStatusText:(NSString *)text {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didChangeStatusText:)]) {
    [delegate browserView:self didChangeStatusText:text];
  }
}

- (void)handleNewTabRequest:(NSString *)url disposition:(FGNavigationDisposition)disposition {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didRequestNewTabWithURL:disposition:)]) {
    [delegate browserView:self didRequestNewTabWithURL:url disposition:disposition];
  }
}

@end
