#ifndef TUIST_APP_H
#define TUIST_APP_H
#include <stdint.h>

int32_t tuist_app_tab_count(void);
// Immutable process-lifetime string; NULL for an invalid index. Never free it.
const char *tuist_app_tab_id(int32_t index);

// Synchronous; invoke on a background thread. The entire operation is serialized.
// request_json and action_json are UTF-8 JSON, NUL-terminated. Do not reenter.
// The host OWNS its response: keep it valid until the NEXT host invocation;
// Rust copies it immediately and NEVER frees it. No free callback is required.
// The host must use platform TLS, forbid insecure non-loopback HTTP and
// cross-origin redirects, and store the opaque vault only in secure storage.
// Rust owns the returned string; release it exactly once with tuist_app_free.
char *tuist_app_call(const char *request_json,
                    char *(*host)(const char *action_json, void *context),
                    void *context);
void tuist_app_free(char *response_json);

#endif
