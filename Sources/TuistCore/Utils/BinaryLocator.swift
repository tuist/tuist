import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case swiftLintNotFound

    var description: String {
        switch self {
        case .swiftLintNotFound:
            return "Couldn't find the swift-lint binary."
        }
    }

    var type: ErrorType {
        switch self {
        case .swiftLintNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the path to the swift-lint binary.
    func swiftLintPath() throws -> AbsolutePath
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    public func swiftLintPath() throws -> AbsolutePath {
        #if DEBUG
            // Used only for debug purposes
            let bundlePath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(RelativePath("vendor"))
        #else
            let bundlePath = AbsolutePath(Bundle(for: BinaryLocator.self).bundleURL.path)
        #endif
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
        ]
        let candidates = paths.map { path in
            path.appending(component: Constants.Vendor.swiftLint)
        }

        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.swiftLintNotFound
        }

        return existingPath
    }
}
