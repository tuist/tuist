import Command
import Path
@_exported import TuistEnvironment

extension Environmenting {
    public var isLegacyModuleCacheEnabled: Bool {
        isVariableTruthy("TUIST_LEGACY_MODULE_CACHE")
    }
}
