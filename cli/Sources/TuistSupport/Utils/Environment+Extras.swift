extension Environmenting {
    public var isLegacyModuleCacheEnabled: Bool {
        isVariableTruthy("TUIST_LEGACY_MODULE_CACHE")
    }
}
