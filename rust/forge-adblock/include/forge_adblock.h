#ifndef FORGE_ADBLOCK_H
#define FORGE_ADBLOCK_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ForgeAdblockEngine ForgeAdblockEngine;

ForgeAdblockEngine *forge_adblock_new(const char *const *rule_paths,
                                      size_t path_count);

void forge_adblock_free(ForgeAdblockEngine *engine);

bool forge_adblock_should_block(const ForgeAdblockEngine *engine,
                                const char *url,
                                const char *source_url,
                                const char *request_type);

size_t forge_adblock_load_resources(ForgeAdblockEngine *engine, const char *path);

char *forge_adblock_cosmetic(const ForgeAdblockEngine *engine, const char *url);

void forge_adblock_string_free(char *text);

size_t forge_adblock_rule_count(const ForgeAdblockEngine *engine);

const char *forge_adblock_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
