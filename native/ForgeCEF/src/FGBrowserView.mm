#import "FGBrowserView.h"
#import "FGBrowserViewInternal.h"

#import "FGClient.h"

#include "include/cef_app.h"
#include "include/cef_browser.h"
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
  BOOL _isLoading;
  BOOL _canGoBack;
  BOOL _canGoForward;
}

- (instancetype)initWithFrame:(NSRect)frame initialURL:(NSString *)url {
  self = [super initWithFrame:frame];
  if (self) {
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
  _client = new FGClient(self);
  _client->SetIgnoreCertificateErrors((_bypassOptions & FGBypassOptionsCertificateErrors) != 0);

  CefWindowInfo window_info;
  const NSRect bounds = self.bounds;
  CefRect rect(0, 0, static_cast<int>(bounds.size.width),
               static_cast<int>(bounds.size.height));
  window_info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(self), rect);

  CefBrowserSettings settings;
  settings.background_color = CefColorSetARGB(255, 0, 0, 0);

  CefBrowserHost::CreateBrowser(window_info, _client.get(),
                                CefString(_pendingURL.UTF8String), settings,
                                nullptr, nullptr);
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

- (void)handleAddressChange:(NSString *)url {
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

- (void)handleNewTabRequest:(NSString *)url disposition:(FGNavigationDisposition)disposition {
  id<FGBrowserViewDelegate> delegate = self.browserDelegate;
  if ([delegate respondsToSelector:@selector(browserView:didRequestNewTabWithURL:disposition:)]) {
    [delegate browserView:self didRequestNewTabWithURL:url disposition:disposition];
  }
}

@end
