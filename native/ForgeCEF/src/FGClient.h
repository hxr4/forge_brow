#ifndef FG_CLIENT_H
#define FG_CLIENT_H

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"
#include "include/cef_find_handler.h"
#include "include/cef_download_handler.h"

@class FGBrowserView;

class FGClient : public CefClient,
                 public CefLifeSpanHandler,
                 public CefLoadHandler,
                 public CefDisplayHandler,
                 public CefRequestHandler,
                 public CefResourceRequestHandler,
                 public CefKeyboardHandler,
                 public CefFindHandler,
                 public CefDownloadHandler {
 public:
  explicit FGClient(FGBrowserView* owner);

  void Detach();
  void Evaluate(const std::string& expression, void (^completion)(id));
  void SetIgnoreCertificateErrors(bool value);
  bool ignore_certificate_errors() const;
  uint64_t blocked_count() const;
  CefRefPtr<CefBrowser> browser();

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
                     bool* no_javascript_access) override;

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  bool DoClose(CefRefPtr<CefBrowser> browser) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override;
  void OnLoadStart(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   TransitionType transition_type) override;
  void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                 CefRefPtr<CefFrame> frame,
                 int httpStatusCode) override;
  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override;

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString>& icon_urls) override;

  bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                          cef_errorcode_t cert_error,
                          const CefString& request_url,
                          CefRefPtr<CefSSLInfo> ssl_info,
                          CefRefPtr<CefCallback> callback) override;

  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request,
      bool is_navigation,
      bool is_download,
      const CefString& request_initiator,
      bool& disable_default_handling) override;

  cef_return_value_t OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser,
                                          CefRefPtr<CefFrame> frame,
                                          CefRefPtr<CefRequest> request,
                                          CefRefPtr<CefCallback> callback) override;

  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override;

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override;

  void OnFindResult(CefRefPtr<CefBrowser> browser,
                    int identifier,
                    int count,
                    const CefRect& selectionRect,
                    int activeMatchOrdinal,
                    bool finalUpdate) override;

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                     const CefKeyEvent& event,
                     CefEventHandle os_event,
                     bool* is_keyboard_shortcut) override;

 private:
  void InjectCosmeticFilters(CefRefPtr<CefFrame> frame);

  __weak FGBrowserView* owner_;

  CefRefPtr<CefDevToolsMessageObserver> devtools_observer_;
  CefRefPtr<CefRegistration> devtools_registration_;

  CefRefPtr<CefBrowser> browser_;
  mutable std::mutex browser_lock_;

  std::string page_url_;
  mutable std::mutex page_url_lock_;

  std::atomic<bool> ignore_certificate_errors_{false};
  std::atomic<uint64_t> blocked_count_{0};
  std::atomic<bool> detached_{false};

  FGClient(const FGClient&) = delete;
  FGClient& operator=(const FGClient&) = delete;

  IMPLEMENT_REFCOUNTING(FGClient);
};

#endif
