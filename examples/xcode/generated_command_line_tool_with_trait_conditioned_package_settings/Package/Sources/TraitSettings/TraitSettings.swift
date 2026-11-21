import TraitSettingsC

#if !Enabled
    #error("The Enabled trait must be an active compilation condition")
#endif

#if !ENABLED_TRAIT_SWIFT_DEFINE
    #error("ENABLED_TRAIT_SWIFT_DEFINE must be defined when the Enabled trait is enabled")
#endif

#if DISABLED_TRAIT_SWIFT_DEFINE
    #error("DISABLED_TRAIT_SWIFT_DEFINE must not be defined when the Disabled trait is disabled")
#endif

public func traitSettingsValue() -> Int32 {
    trait_settings_c_value()
}
