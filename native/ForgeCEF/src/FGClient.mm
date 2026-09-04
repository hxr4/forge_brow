#import "FGClient.h"

#import "FGAdblock.h"
#import "FGAdblockInternal.h"
#import "FGBrowserView.h"
#import "FGBrowserViewInternal.h"
#import "FGDownloads.h"

#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/cef_ssl_info.h"

#include "forge_schemes.h"

namespace {

NSString* ToNSString(const CefString& value) {
  const std::string utf8 = value.ToString();
  NSString* result = [[NSString alloc] initWithBytes:utf8.data()
                                              length:utf8.size()
                                            encoding:NSUTF8StringEncoding];
  return result ?: @"";
}

const char* AdblockTypeForResourceType(cef_resource_type_t type) {
  switch (type) {
    case RT_MAIN_FRAME:
      return "document";
    case RT_SUB_FRAME:
      return "subdocument";
    case RT_STYLESHEET:
      return "stylesheet";
    case RT_SCRIPT:
      return "script";
    case RT_IMAGE:
      return "image";
    case RT_FONT_RESOURCE:
      return "font";
    case RT_OBJECT:
      return "object";
    case RT_MEDIA:
      return "media";
    case RT_XHR:
      return "xmlhttprequest";
    case RT_PING:
      return "ping";
    case RT_CSP_REPORT:
      return "csp";
    default:
      return "other";
  }
}

std::string EscapeForJSString(const std::string& input) {
  std::string out;
  out.reserve(input.size() + 32);
  for (char c : input) {
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"':  out += "\\\""; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '<':  out += "\\x3C"; break;
      default:   out += c;
    }
  }
  return out;
}


class FGFaviconCallback : public CefDownloadImageCallback {
 public:
  explicit FGFaviconCallback(FGBrowserView* owner) : owner_(owner) {}

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    if (!image) {
      return;
    }
    int width = 0;
    int height = 0;
    CefRefPtr<CefBinaryValue> png = image->GetAsPNG(1.0f, true, width, height);
    if (!png) {
      return;
    }
    const size_t size = png->GetSize();
    if (size == 0) {
      return;
    }
    NSMutableData* data = [NSMutableData dataWithLength:size];
    if (png->GetData(data.mutableBytes, size, 0) != size) {
      return;
    }
    __weak FGBrowserView* owner = owner_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSImage* icon = [[NSImage alloc] initWithData:data];
      if (icon.isValid) {
        [owner handleFaviconChange:icon];
      }
    });
  }

 private:
  __weak FGBrowserView* owner_;
  IMPLEMENT_REFCOUNTING(FGFaviconCallback);
};

bool IsInternalScheme(const std::string& url) {
  if (url.empty()) {
    return true;
  }
  static const char* kInternal[] = {"forge://", "devtools://", "chrome://",
                                    "chrome-devtools://", "data:", "blob:", "about:"};
  for (const char* prefix : kInternal) {
    if (url.rfind(prefix, 0) == 0) {
      return true;
    }
  }
  return false;
}

}  // namespace

FGClient::FGClient(FGBrowserView* owner) : owner_(owner) {}

void FGClient::Detach() {
  detached_.store(true, std::memory_order_relaxed);
  owner_ = nil;
}

void FGClient::SetIgnoreCertificateErrors(bool value) {
  ignore_certificate_errors_.store(value, std::memory_order_relaxed);
}

bool FGClient::ignore_certificate_errors() const {
  return ignore_certificate_errors_.load(std::memory_order_relaxed);
}

uint64_t FGClient::blocked_count() const {
  return blocked_count_.load(std::memory_order_relaxed);
}

CefRefPtr<CefBrowser> FGClient::browser() {
  std::lock_guard<std::mutex> guard(browser_lock_);
  return browser_;
}

bool FGClient::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             int popup_id,
                             const CefString& target_url,
                             const CefString& target_frame_name,
                             WindowOpenDisposition target_disposition,
                             bool user_gesture,
                             const CefPopupFeatures& popupFeatures,
                             CefWindowInfo& windowInfo,
                             CefRefPtr<CefClient>& client,
                             CefBrowserSettings& settings,
                             CefRefPtr<CefDictionaryValue>& extra_info,
                             bool* no_javascript_access) {
  if (!user_gesture) {
    [FGAdblock.shared noteBlockedPopup];
    return true;
  }

  NSString* url = ToNSString(target_url);
  const FGNavigationDisposition disposition =
      (target_disposition == CEF_WOD_NEW_BACKGROUND_TAB)
          ? FGNavigationDispositionNewBackgroundTab
          : FGNavigationDispositionNewForegroundTab;

  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleNewTabRequest:url disposition:disposition];
  });
  return true;
}

void FGClient::InjectCosmeticFilters(CefRefPtr<CefFrame> frame) {
  if (!frame || !frame->IsMain()) {
    return;
  }
  const std::string url = frame->GetURL().ToString();
  if (IsInternalScheme(url)) {
    return;
  }

  NSString* json = [FGAdblock.shared cosmeticJSONForURL:url.c_str()];
  if (json.length == 0) {
    return;
  }

  NSData* data = [json dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![parsed isKindOfClass:NSDictionary.class]) {
    return;
  }

  NSArray* hide = parsed[@"hide"];
  NSString* injectedProbe = parsed[@"script"];
  NSLog(@"[forge] cosmetic %@ -> %lu selectors, %lu bytes of scriptlet",
        [NSString stringWithUTF8String:url.c_str()],
        (unsigned long)([hide isKindOfClass:NSArray.class] ? hide.count : 0),
        (unsigned long)([injectedProbe isKindOfClass:NSString.class] ? injectedProbe.length : 0));

  if ([hide isKindOfClass:NSArray.class] && hide.count > 0) {
    NSString* joined = [hide componentsJoinedByString:@","];
    std::string css = std::string(joined.UTF8String) + "{display:none !important;}";
    const std::string script =
        "(function(){var id='__forge_cosmetic__';var s=document.getElementById(id);"
        "if(!s){s=document.createElement('style');s.id=id;"
        "(document.head||document.documentElement).appendChild(s);}"
        "s.textContent=\"" + EscapeForJSString(css) + "\";})();";
    frame->ExecuteJavaScript(script, frame->GetURL(), 0);
  }

  NSString* injected = parsed[@"script"];
  if ([injected isKindOfClass:NSString.class] && injected.length > 0) {
    frame->ExecuteJavaScript(CefString(injected.UTF8String), frame->GetURL(), 0);
  }
}

void FGClient::OnLoadStart(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           TransitionType transition_type) {
  InjectCosmeticFilters(frame);
}

void FGClient::OnLoadEnd(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         int httpStatusCode) {
  InjectCosmeticFilters(frame);
}

void FGClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  {
    std::lock_guard<std::mutex> guard(browser_lock_);
    browser_ = browser;
  }
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleBrowserCreated];
  });
}

bool FGClient::DoClose(CefRefPtr<CefBrowser> browser) {
  return true;
}

void FGClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  {
    std::lock_guard<std::mutex> guard(browser_lock_);
    browser_ = nullptr;
  }
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleBrowserClosed];
  });
}

void FGClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                    bool isLoading,
                                    bool canGoBack,
                                    bool canGoForward) {
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleLoadingState:isLoading canGoBack:canGoBack canGoForward:canGoForward];
  });
}

void FGClient::OnLoadError(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           ErrorCode errorCode,
                           const CefString& errorText,
                           const CefString& failedUrl) {
  if (errorCode == ERR_ABORTED) {
    return;
  }
  if (frame && !frame->IsMain()) {
    return;
  }
  NSString* message = ToNSString(errorText);
  NSString* url = ToNSString(failedUrl);
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleLoadError:message url:url];
  });
}

void FGClient::OnAddressChange(CefRefPtr<CefBrowser> browser,
                               CefRefPtr<CefFrame> frame,
                               const CefString& url) {
  if (frame && !frame->IsMain()) {
    return;
  }
  {
    std::lock_guard<std::mutex> guard(page_url_lock_);
    page_url_ = url.ToString();
  }
  NSString* value = ToNSString(url);
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleAddressChange:value];
  });
}

void FGClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  NSString* value = ToNSString(title);
  __weak FGBrowserView* owner = owner_;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleTitleChange:value];
  });
}

void FGClient::OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                                  const std::vector<CefString>& icon_urls) {
  if (!browser || icon_urls.empty()) {
    return;
  }
  FGBrowserView* owner = owner_;
  if (!owner) {
    return;
  }
  browser->GetHost()->DownloadImage(icon_urls.front(), true, 32, false,
                                    new FGFaviconCallback(owner));
}

bool FGClient::OnCertificateError(CefRefPtr<CefBrowser> browser,
                                  cef_errorcode_t cert_error,
                                  const CefString& request_url,
                                  CefRefPtr<CefSSLInfo> ssl_info,
                                  CefRefPtr<CefCallback> callback) {
  if (!ignore_certificate_errors_.load(std::memory_order_relaxed)) {
    return false;
  }
  callback->Continue();
  return true;
}

CefRefPtr<CefResourceRequestHandler> FGClient::GetResourceRequestHandler(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    CefRefPtr<CefRequest> request,
    bool is_navigation,
    bool is_download,
    const CefString& request_initiator,
    bool& disable_default_handling) {
  return this;
}

cef_return_value_t FGClient::OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser,
                                                  CefRefPtr<CefFrame> frame,
                                                  CefRefPtr<CefRequest> request,
                                                  CefRefPtr<CefCallback> callback) {
  const cef_resource_type_t resource_type = request->GetResourceType();
  if (resource_type == RT_MAIN_FRAME || resource_type == RT_FAVICON) {
    return RV_CONTINUE;
  }

  const std::string url = request->GetURL().ToString();
  if (IsInternalScheme(url)) {
    return RV_CONTINUE;
  }

  std::string source_url;
  {
    std::lock_guard<std::mutex> guard(page_url_lock_);
    source_url = page_url_;
  }

  const char* request_type = AdblockTypeForResourceType(resource_type);
  FGAdblock* blocker = FGAdblock.shared;
  if (![blocker shouldBlockURL:url.c_str()
                     sourceURL:source_url.c_str()
                   requestType:request_type]) {
    return RV_CONTINUE;
  }

  [blocker noteBlockedRequestOfType:request_type];
  blocked_count_.fetch_add(1, std::memory_order_relaxed);
  return RV_CANCEL;
}

bool FGClient::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefDownloadItem> download_item,
                                const CefString& suggested_name,
                                CefRefPtr<CefBeforeDownloadCallback> callback) {
  callback->Continue(CefString(), true);
  return true;
}

void FGClient::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                 CefRefPtr<CefDownloadItem> download_item,
                                 CefRefPtr<CefDownloadItemCallback> callback) {
  if (!download_item->IsValid()) {
    return;
  }
  NSString* name = ToNSString(download_item->GetSuggestedFileName());
  NSString* path = ToNSString(download_item->GetFullPath());
  NSString* url = ToNSString(download_item->GetURL());
  const int percent = download_item->GetPercentComplete();
  const BOOL complete = download_item->IsComplete();
  const BOOL cancelled = download_item->IsCanceled();
  const int64_t received = download_item->GetReceivedBytes();
  const int64_t total = download_item->GetTotalBytes();
  const uint32_t identifier = download_item->GetId();

  dispatch_async(dispatch_get_main_queue(), ^{
    [FGDownloads.shared updateWithIdentifier:identifier
                                        name:name
                                        path:path
                                         url:url
                                     percent:percent
                                    received:received
                                       total:total
                                    complete:complete
                                   cancelled:cancelled];
  });
}

void FGClient::OnFindResult(CefRefPtr<CefBrowser> browser,
                            int identifier,
                            int count,
                            const CefRect& selectionRect,
                            int activeMatchOrdinal,
                            bool finalUpdate) {
  __weak FGBrowserView* owner = owner_;
  const NSInteger total = count;
  const NSInteger active = activeMatchOrdinal;
  dispatch_async(dispatch_get_main_queue(), ^{
    [owner handleFindMatchCount:total active:active];
  });
}

bool FGClient::OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                             const CefKeyEvent& event,
                             CefEventHandle os_event,
                             bool* is_keyboard_shortcut) {
  const bool command_down = (event.modifiers & EVENTFLAG_COMMAND_DOWN) != 0;
  if (event.type == KEYEVENT_RAWKEYDOWN && command_down && event.windows_key_code == 'K') {
    __weak FGBrowserView* owner = owner_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [owner handleCommandPaletteShortcut];
    });
    return true;
  }
  return false;
}
