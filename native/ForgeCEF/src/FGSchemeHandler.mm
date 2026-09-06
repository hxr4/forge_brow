#import "FGSchemeHandler.h"

#import "FGAdblock.h"
#import "FGStateStore.h"
#import "FGStateStoreInternal.h"

#include <algorithm>
#include <mutex>
#include <string>
#include <string.h>
#include <vector>

#include "include/cef_parser.h"
#include "include/cef_resource_handler.h"
#include "include/cef_request.h"
#include "include/cef_response.h"
#include "include/wrapper/cef_helpers.h"

#include "forge_schemes.h"

namespace {

std::string gWebRoot;
std::mutex gWebRootLock;

std::string WebRoot() {
  std::lock_guard<std::mutex> guard(gWebRootLock);
  return gWebRoot;
}

std::string MimeTypeForPath(const std::string& path) {
  const size_t dot = path.rfind('.');
  if (dot == std::string::npos) {
    return "application/octet-stream";
  }
  const std::string ext = path.substr(dot + 1);
  if (ext == "html") return "text/html";
  if (ext == "css") return "text/css";
  if (ext == "js") return "text/javascript";
  if (ext == "json") return "application/json";
  if (ext == "svg") return "image/svg+xml";
  if (ext == "png") return "image/png";
  if (ext == "woff2") return "font/woff2";
  return "application/octet-stream";
}

bool PathIsSafe(const std::string& path) {
  return path.find("..") == std::string::npos;
}

std::string ReadFile(const std::string& absolute) {
  NSString* path = [NSString stringWithUTF8String:absolute.c_str()];
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (!data) {
    return std::string();
  }
  return std::string(static_cast<const char*>(data.bytes), data.length);
}

std::string JSONFromDictionary(NSDictionary* dictionary) {
  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
  if (!data) {
    return "{}";
  }
  return std::string(static_cast<const char*>(data.bytes), data.length);
}

std::string BuildStateJSON() {
  NSMutableDictionary* payload = [[FGStateStore.shared snapshot] mutableCopy];
  FGAdblock* blocker = FGAdblock.shared;
  payload[@"adblock"] = @{
    @"ready" : @(blocker.isReady),
    @"ruleCount" : @(blocker.ruleCount),
    @"blockedCount" : @(blocker.blockedCount),
    @"estimatedBytesSaved" : @(blocker.estimatedBytesSaved),
  };
  return JSONFromDictionary(payload);
}

std::string ReadPostBody(CefRefPtr<CefRequest> request) {
  CefRefPtr<CefPostData> post_data = request->GetPostData();
  if (!post_data) {
    return std::string();
  }
  CefPostData::ElementVector elements;
  post_data->GetElements(elements);
  std::string body;
  for (const auto& element : elements) {
    if (element->GetType() != PDE_TYPE_BYTES) {
      continue;
    }
    const size_t count = element->GetBytesCount();
    if (count == 0) {
      continue;
    }
    std::string chunk(count, '\0');
    element->GetBytes(count, chunk.data());
    body.append(chunk);
  }
  return body;
}

class FGResourceHandler : public CefResourceHandler {
 public:
  FGResourceHandler(std::string body, std::string mime_type, int status)
      : body_(std::move(body)), mime_type_(std::move(mime_type)), status_(status) {}

  bool Open(CefRefPtr<CefRequest> request,
            bool& handle_request,
            CefRefPtr<CefCallback> callback) override {
    handle_request = true;
    return true;
  }

  void GetResponseHeaders(CefRefPtr<CefResponse> response,
                          int64_t& response_length,
                          CefString& redirectUrl) override {
    response->SetMimeType(mime_type_);
    response->SetStatus(status_);
    CefResponse::HeaderMap headers;
    headers.insert(std::make_pair("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"));
    headers.insert(std::make_pair("Pragma", "no-cache"));
    headers.insert(std::make_pair("Expires", "0"));
    response->SetHeaderMap(headers);
    response_length = static_cast<int64_t>(body_.size());
  }

  bool Read(void* data_out,
            int bytes_to_read,
            int& bytes_read,
            CefRefPtr<CefResourceReadCallback> callback) override {
    bytes_read = 0;
    if (offset_ >= body_.size()) {
      return false;
    }
    const size_t available = body_.size() - offset_;
    const size_t transfer = std::min(available, static_cast<size_t>(bytes_to_read));
    memcpy(data_out, body_.data() + offset_, transfer);
    offset_ += transfer;
    bytes_read = static_cast<int>(transfer);
    return true;
  }

  void Cancel() override {}

 private:
  std::string body_;
  std::string mime_type_;
  int status_;
  size_t offset_ = 0;

  FGResourceHandler(const FGResourceHandler&) = delete;
  FGResourceHandler& operator=(const FGResourceHandler&) = delete;

  IMPLEMENT_REFCOUNTING(FGResourceHandler);
};

CefRefPtr<CefResourceHandler> NotFound() {
  return new FGResourceHandler("not found", "text/plain", 404);
}

class FGSchemeHandlerFactory : public CefSchemeHandlerFactory {
 public:
  CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& scheme_name,
                                       CefRefPtr<CefRequest> request) override {
    CefURLParts parts;
    if (!CefParseURL(request->GetURL(), parts)) {
      return NotFound();
    }
    std::string path = CefString(&parts.path).ToString();
    if (path.empty() || path == "/") {
      path = "/index.html";
    }
    if (!PathIsSafe(path)) {
      return NotFound();
    }

    if (path == "/api/state") {
      return new FGResourceHandler(BuildStateJSON(), "application/json", 200);
    }

    if (path == "/api/command") {
      const std::string body = ReadPostBody(request);
      NSData* data = [NSData dataWithBytes:body.data() length:body.size()];
      NSDictionary* parsed = nil;
      if (data.length > 0) {
        parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      }
      if (![parsed isKindOfClass:NSDictionary.class]) {
        return new FGResourceHandler("{\"ok\":false,\"error\":\"bad request\"}",
                                     "application/json", 400);
      }
      NSString* action = parsed[@"action"];
      NSDictionary* payload = parsed[@"payload"];
      if (![action isKindOfClass:NSString.class]) {
        return new FGResourceHandler("{\"ok\":false,\"error\":\"missing action\"}",
                                     "application/json", 400);
      }
      NSDictionary* safePayload =
          [payload isKindOfClass:NSDictionary.class] ? payload : @{};
      dispatch_async(dispatch_get_main_queue(), ^{
        [FGStateStore.shared dispatchAction:action payload:safePayload];
      });
      return new FGResourceHandler("{\"ok\":true}", "application/json", 200);
    }

    const std::string root = WebRoot();
    if (root.empty()) {
      return NotFound();
    }
    const std::string absolute = root + path;
    const std::string contents = ReadFile(absolute);
    if (contents.empty()) {
      return NotFound();
    }
    return new FGResourceHandler(contents, MimeTypeForPath(path), 200);
  }

 private:
  IMPLEMENT_REFCOUNTING(FGSchemeHandlerFactory);
};

}  // namespace

void FGSetWebResourceRoot(const std::string& path) {
  std::lock_guard<std::mutex> guard(gWebRootLock);
  gWebRoot = path;
}

void FGRegisterSchemeHandlerFactory() {
  CefRegisterSchemeHandlerFactory(kForgeScheme, kForgeHost, new FGSchemeHandlerFactory());
}

void FGRegisterSchemeHandlerFactoryOn(CefRefPtr<CefRequestContext> context) {
  if (!context) {
    return;
  }
  context->RegisterSchemeHandlerFactory(kForgeScheme, kForgeHost, new FGSchemeHandlerFactory());
}
