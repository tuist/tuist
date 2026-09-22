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
    /// Resolving the endpoint already waits a bounded time for a cache instance that is being
    /// prepared. A remote cache that is still not ready after that, has no endpoint, or is
    /// temporarily unreachable never fails the command: a cache miss is always safe, so the run continues on the local cache
    /// and says why. Errors that waiting does not fix, such as rejected credentials or a malformed
    /// endpoint, are rethrown.
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
        case .endpointBeingPrepared:
            return .alert(
                "The remote cache is still being prepared.",
                takeaway: "This run uses the local cache. The remote cache is used as soon as it is ready."
            )
        case .noEndpointsAvailable:
            return .alert(
                "No remote cache endpoint is available.",
                takeaway: "This run uses the local cache."
            )
        case .noReachableEndpoints:
            return temporarilyUnavailableWarning
        case .invalidURL, nil:
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
