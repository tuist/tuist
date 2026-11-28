#include "TraitSettingsC.h"

#ifndef ENABLED_TRAIT_C_DEFINE
#error "ENABLED_TRAIT_C_DEFINE must be defined when the Enabled trait is enabled"
#endif

#ifndef MACOS_ENABLED_TRAIT_C_DEFINE
#error "MACOS_ENABLED_TRAIT_C_DEFINE must be defined on macOS when the Enabled trait is enabled"
#endif

#ifdef DISABLED_TRAIT_C_DEFINE
#error "DISABLED_TRAIT_C_DEFINE must not be defined when the Disabled trait is disabled"
#endif

int trait_settings_c_value(void) {
    return 42;
}
