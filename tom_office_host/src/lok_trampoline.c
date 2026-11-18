// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// The C part of tom_office_host, built by hook/build.dart.
//
// 1. tom_lok_init_2: the headers' lok_init_2 is a static inline function,
//    which FFI cannot bind; this exports it unchanged.
// 2. tom_lok_callback: the callback registered with LibreOfficeKit. It runs
//    on LibreOffice's threads, and LibreOfficeKit frees the payload when it
//    returns, so it copies the payload (strdup) and hands the copy to the
//    Dart listener (a NativeCallable.listener, which returns at once). Dart
//    frees the copy with tom_lok_free.
// 3. The password answer. LibreOfficeKit asks for a password with a
//    DOCUMENT_PASSWORD(_TO_MODIFY) callback while documentLoadWithOptions
//    blocks the helper's thread, so a Dart listener cannot answer in time:
//    the trampoline answers from LibreOffice's thread with the answer the
//    helper armed before the load. It answers once per arming (a wrong
//    password is then answered NULL, which ends the load instead of asking
//    for ever), and records which kinds were asked for. The password never
//    reaches the Dart listener.

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
                               intptr_t tag);

static _Atomic(TomLokListener) g_listener = NULL;
static LibreOfficeKit *g_password_kit = NULL;
static char *g_password = NULL;
static atomic_int g_password_armed = 0;
static atomic_int g_password_asked = 0;

TOM_LOK_EXPORT LibreOfficeKit *tom_lok_init_2(const char *install_path,
                                              const char *user_profile_url) {
  return lok_init_2(install_path, user_profile_url);
}

TOM_LOK_EXPORT void tom_lok_set_listener(TomLokListener listener) {
  atomic_store(&g_listener, listener);
}

// Arms the answer for the next password request ([password] NULL: cancel)
// and clears what was asked for.
TOM_LOK_EXPORT void tom_lok_set_password_answer(LibreOfficeKit *kit,
                                                const char *password) {
  free(g_password);
  g_password = password ? strdup(password) : NULL;
  g_password_kit = kit;
  atomic_store(&g_password_asked, 0);
  atomic_store(&g_password_armed, 1);
}

// Which password kinds LibreOfficeKit asked for since the last arming:
// bit 0 the password to open, bit 1 the password to modify; bit 2 when it
// asked again after the armed answer was used (a wrong password).
TOM_LOK_EXPORT int tom_lok_password_asked(void) {
  return atomic_load(&g_password_asked);
}

TOM_LOK_EXPORT void tom_lok_callback(int type, const char *payload,
                                     void *data) {
  if ((type == TOM_LOK_CALLBACK_DOCUMENT_PASSWORD ||
       type == TOM_LOK_CALLBACK_DOCUMENT_PASSWORD_TO_MODIFY) &&
      g_password_kit != NULL && payload != NULL) {
    int kind = type == TOM_LOK_CALLBACK_DOCUMENT_PASSWORD ? 1 : 2;
    int armed = atomic_exchange(&g_password_armed, 0);
    atomic_fetch_or(&g_password_asked, armed ? kind : (kind | 4));
    g_password_kit->pClass->setDocumentPassword(g_password_kit, payload,
                                                armed ? g_password : NULL);
  }
  TomLokListener listener = atomic_load(&g_listener);
  if (listener == NULL) return;
  size_t length = payload ? strlen(payload) : 0;
  char *copy = payload ? strdup(payload) : NULL;
  listener(type, copy, (int64_t)length, (intptr_t)data);
}

TOM_LOK_EXPORT LibreOfficeKitCallback tom_lok_callback_pointer(void) {
  return tom_lok_callback;
}

TOM_LOK_EXPORT void tom_lok_free(void *pointer) { free(pointer); }
