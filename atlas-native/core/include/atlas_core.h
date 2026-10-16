#ifndef ATLAS_CORE_H
#define ATLAS_CORE_H

#include <stdint.h>

int32_t atlas_section_count(void);

/* Fields: 0 = title, 1 = description, 2 = HTTPS URL, 3 = native screen key.
 * Returns an immutable UTF-8 C string valid for the process lifetime, or NULL
 * for invalid input. The caller must never free or mutate the returned string.
 */
const char *atlas_section_field(int32_t section, int32_t field);

/* The byte API excludes the NUL terminator and returns -1 for invalid input. */
int32_t atlas_section_field_length(int32_t section, int32_t field);
int32_t atlas_section_field_byte(int32_t section, int32_t field, int32_t offset);

#endif
