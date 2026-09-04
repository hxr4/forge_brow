#include "forge_schemes.h"

const char kForgeScheme[] = "forge";
const char kForgeHost[] = "home";
const char kForgeHomeURL[] = "forge://home/";

void ForgeRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) {
  registrar->AddCustomScheme(kForgeScheme,
                             CEF_SCHEME_OPTION_STANDARD |
                                 CEF_SCHEME_OPTION_SECURE |
                                 CEF_SCHEME_OPTION_CORS_ENABLED |
                                 CEF_SCHEME_OPTION_FETCH_ENABLED);
}
