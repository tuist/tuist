#ifndef ATLAS_AUTH_H
#define ATLAS_AUTH_H

/* Blocking JSON command interface. Call from a background executor.
 * Input is borrowed for this call. The result is an owned UTF-8 JSON string;
 * the caller must release it exactly once using atlas_auth_free.
 * Neither input nor output may be logged: both can contain credentials.
 */
char *atlas_auth_execute(const char *input);
void atlas_auth_free(char *output);

#endif
