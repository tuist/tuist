import Noora
import TuistAlert
import TuistCAS
import TuistConfig
import TuistCore
import TuistServer

extension CacheStorageFactorying {
    /// The cache storage for `config`, or one backed by the local cache alone when the remote cache
    /// can't be used right now.
    ///
    /// Missing self-hosted endpoint configuration and transient transport failures use local
    /// storage with a warning. Rejected credentials and malformed endpoint settings are rethrown.
    func cacheStorageFallingBackToLocal(config: Tuist) async throws -> CacheStoring {
        do {
            return try await cacheStorage(config: config)
        } catch {
            guard let warning = Self.localFallbackWarning(for: error) else { throw error }
            if !AlertController.current.warnings().contains(warning) {
                AlertController.current.warning(warning)
            }
            return try await cacheLocalStorage()
        }
    }

    static func localFallbackWarning(for error: Error) -> WarningAlert? {
        switch error as? CacheURLStoreError {
        case .missingEndpointOverride:
            return .alert(
                "Remote caching requires TUIST_CACHE_ENDPOINT for this server.",
                takeaway: "This run uses the local cache. Set the override to enable remote caching."
            )
        case .invalidURL, .invalidAccountHandle, nil:
            return ServerErrorClassifier.isTransient(error) ? temporarilyUnavailableWarning : nil
        }
    }

    private static var temporarilyUnavailableWarning: WarningAlert {
        .alert(
            "The remote cache is temporarily unavailable.",
            takeaway: "This run uses the local cache."
        )
    }
}
