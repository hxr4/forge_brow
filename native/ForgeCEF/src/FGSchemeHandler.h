#ifndef FG_SCHEME_HANDLER_H
#define FG_SCHEME_HANDLER_H

#include <string>

#include "include/cef_request_context.h"
#include "include/cef_scheme.h"

void FGSetWebResourceRoot(const std::string& path);
void FGRegisterSchemeHandlerFactory();
void FGRegisterSchemeHandlerFactoryOn(CefRefPtr<CefRequestContext> context);

#endif
