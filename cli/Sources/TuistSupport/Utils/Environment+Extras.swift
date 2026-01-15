extension Environmenting {
    public var isExperimentalRegionalCacheEnabled: Bool {
        isVariableTruthy("TUIST_EXPERIMENTAL_MODULE_CACHE")
    }
}
