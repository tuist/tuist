#ifndef ATLAS_CORE_H
#define ATLAS_CORE_H

#include <stdint.h>

int32_t atlas_section_count(void);

/* Fields: 0 = title, 1 = description, 2 = HTTPS URL, 3 = native screen key,
 * 4 = stable ID, 5 = group ID, 6 = shortcut (1/0), 7 = required web scope.
 * Scope metadata describes browser access, not a local authorization grant.
 * Returns an immutable UTF-8 C string valid for the process lifetime, or NULL
 * for invalid input. The caller must never free or mutate the returned string.
 */
const char *atlas_section_field(int32_t section, int32_t field);

/* The byte API excludes the NUL terminator and returns -1 for invalid input. */
int32_t atlas_section_field_length(int32_t section, int32_t field);
int32_t atlas_section_field_byte(int32_t section, int32_t field, int32_t offset);

/* Groups: 0 = title, 1 = description, 2 = stable ID, 3 = parent ID (empty
 * for roots), 4 = placement (workspace/settings). Same ownership/byte rules.
 */
int32_t atlas_group_count(void);
const char *atlas_group_field(int32_t group, int32_t field);
int32_t atlas_group_field_length(int32_t group, int32_t field);
int32_t atlas_group_field_byte(int32_t group, int32_t field, int32_t offset);

/* Deep-link capabilities: 0 = native screen key, 1 = accepts record UUID (1/0).
 * Same immutable string ownership and invalid-input rules as the catalog. */
int32_t atlas_destination_count(void);
const char *atlas_destination_field(int32_t destination, int32_t field);
int32_t atlas_destination_field_length(int32_t destination, int32_t field);
int32_t atlas_destination_field_byte(int32_t destination, int32_t field, int32_t offset);

#endif
