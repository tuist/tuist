import ArgumentParser
import Foundation
import TuistCacheCommand
import TuistEnvironment
import TuistExtension
import TuistTesting

#if canImport(TuistCacheEE)
    import TuistKit
#endif

extension TuistTest {
    public static func run(
        _ command: CacheCommand.Type,
        _ arguments: [String] = [],
        options _: Set<TuistTestRunOption> = Set()
    ) async throws {
        if let mockEnvironment = Environment.mocked {
            mockEnvironment.processId = UUID().uuidString
        }

        let execute: () async throws -> Void = {
            var parsedCommand = try command.parseAsRoot(arguments)
            if var asyncCommand = parsedCommand as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try parsedCommand.run()
            }
        }

        #if canImport(TuistCacheEE)
            try await TuistExtension.Extension.$cacheService
                .withValue(CacheWarmCommandService()) {
                    try await TuistExtension.Extension.$hashCacheService
                        .withValue(HashCacheCommandService()) {
                            try await execute()
                        }
                }
        #else
            try await execute()
        #endif
    }
}
