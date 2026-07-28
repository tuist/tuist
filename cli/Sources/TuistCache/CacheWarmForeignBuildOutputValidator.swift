import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

public enum CacheWarmForeignBuildOutputValidatorError: LocalizedError, Equatable {
    case unsupported(scratchDirectory: AbsolutePath, targetNames: [String])

    public var errorDescription: String? {
        switch self {
        case let .unsupported(scratchDirectory, targetNames):
            return """
            The cache warm scratch directory at \(scratchDirectory
                .pathString) cannot be used with foreign build targets: \(targetNames.joined(separator: ", ")). \
            Foreign build scripts control their output locations, so Tuist cannot guarantee that every build output stays inside the scratch directory.
            """
        }
    }
}

@Mockable
public protocol CacheWarmForeignBuildOutputValidating {
    func validate(
        targets: [GraphTarget],
        scratchDirectory: CacheWarmScratchDirectory
    ) throws
}

public struct CacheWarmForeignBuildOutputValidator: CacheWarmForeignBuildOutputValidating {
    public init() {}

    public func validate(
        targets: [GraphTarget],
        scratchDirectory: CacheWarmScratchDirectory
    ) throws {
        guard case let .callerOwned(path) = scratchDirectory else {
            return
        }

        let targetNames = targets
            .filter { $0.target.foreignBuild != nil }
            .map(\.target.name)
            .sorted()
        guard !targetNames.isEmpty else {
            return
        }

        throw CacheWarmForeignBuildOutputValidatorError.unsupported(
            scratchDirectory: path,
            targetNames: targetNames
        )
    }
}
