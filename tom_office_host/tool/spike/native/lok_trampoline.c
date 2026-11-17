// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// The C side of the LibreOfficeKit spike (spike code, see ../README.md).
//
// 1. tom_lok_init_2: the headers' lok_init_2 is a static inline function,
//    which FFI cannot bind; this exports it unchanged.
// 2. tom_lok_callback: the callback registered with LibreOfficeKit. It runs
//    on LibreOffice's threads; LibreOfficeKit frees the payload when it
//    returns, so it copies the payload (strdup) and hands the copy to the
//    Dart listener (a NativeCallable.listener, which returns at once). Dart
//    frees the copy with tom_lok_free. For the spike's integrity check it
//    also passes an FNV-1a hash and the length of the original payload, and
//    counts the callbacks it saw.

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define LOK_USE_UNSTABLE_API
#include "LibreOfficeKitInit.h"

// From LibreOfficeKitEnums.h, whose inline helpers are C++ only.
#define TOM_LOK_CALLBACK_DOCUMENT_PASSWORD 20
#define TOM_LOK_CALLBACK_DOCUMENT_PASSWORD_TO_MODIFY 21

#define TOM_LOK_EXPORT __attribute__((visibility("default")))

typedef void (*TomLokListener)(int32_t type, char *payload, int64_t length,
                               uint64_t hash, intptr_t tag);

static _Atomic(TomLokListener) g_listener = NULL;
static LibreOfficeKit *g_password_kit = NULL;
static char *g_password = NULL;
static atomic_long g_count = 0;

static uint64_t fnv1a(const char *text, size_t length) {
  uint64_t hash = 1469598103934665603ULL;
  for (size_t i = 0; i < length; i++) {
    hash ^= (unsigned char)text[i];
    hash *= 1099511628211ULL;
  }
  return hash;
}

TOM_LOK_EXPORT LibreOfficeKit *tom_lok_init_2(const char *install_path,
                                              const char *user_profile_url) {
  return lok_init_2(install_path, user_profile_url);
}

TOM_LOK_EXPORT void tom_lok_set_listener(TomLokListener listener) {
  atomic_store(&g_listener, listener);
}

TOM_LOK_EXPORT long tom_lok_callback_count(void) {
  return atomic_load(&g_count);
}

// A password answer given in advance. LibreOfficeKit asks for a password
// with an office-level DOCUMENT_PASSWORD(_TO_MODIFY) callback while
// documentLoad blocks the caller, so a Dart listener could not answer in
// time; the trampoline answers from LibreOffice's thread.
TOM_LOK_EXPORT void tom_lok_set_password_answer(LibreOfficeKit *kit,
                                                const char *password) {
  free(g_password);
  g_password = password ? strdup(password) : NULL;
  g_password_kit = kit;
}

TOM_LOK_EXPORT void tom_lok_callback(int type, const char *payload,
                                     void *data) {
  atomic_fetch_add(&g_count, 1);
  if ((type == TOM_LOK_CALLBACK_DOCUMENT_PASSWORD ||
       type == TOM_LOK_CALLBACK_DOCUMENT_PASSWORD_TO_MODIFY) &&
      g_password_kit != NULL && payload != NULL) {
    g_password_kit->pClass->setDocumentPassword(g_password_kit, payload,
                                                g_password);
  }
  TomLokListener listener = atomic_load(&g_listener);
  if (listener == NULL) return;
  size_t length = payload ? strlen(payload) : 0;
  char *copy = payload ? strdup(payload) : NULL;
  listener(type, copy, (int64_t)length, payload ? fnv1a(payload, length) : 0,
           (intptr_t)data);
}

TOM_LOK_EXPORT LibreOfficeKitCallback tom_lok_callback_pointer(void) {
  return tom_lok_callback;
}

TOM_LOK_EXPORT void tom_lok_free(void *pointer) { free(pointer); }

TOM_LOK_EXPORT uint64_t tom_lok_fnv1a(const char *text, int64_t length) {
  return fnv1a(text, (size_t)length);
}
