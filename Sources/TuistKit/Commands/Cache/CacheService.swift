import Foundation

public protocol CacheServicing {
    func run(
        path directory: String?,
        configuration: String?,
        targetsToBinaryCache: Set<String>,
        externalOnly: Bool,
        generateOnly: Bool
    ) async throws
}

final class EmptyCacheService: CacheServicing {
    func run(
        path _: String?,
        configuration _: String?,
        targetsToBinaryCache _: Set<String>,
        externalOnly _: Bool,
        generateOnly _: Bool
    ) async throws {
        logger
            .notice(
                "Caching is currently not opensourced. Please, report issues with caching on GitHub and the Tuist team will take a look."
            )
    }
}
