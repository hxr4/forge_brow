#ifndef FORGE_SCHEMES_H
#define FORGE_SCHEMES_H

#include "include/cef_scheme.h"

extern const char kForgeScheme[];
extern const char kForgeHost[];
extern const char kForgeHomeURL[];

void ForgeRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar);

#endif
