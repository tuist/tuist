import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case swiftLintNotFound
    case swiftDocNotFound

    var description: String {
        switch self {
        case .swiftLintNotFound:
            return "Couldn't find the swift-lint binary."
        case .swiftDocNotFound:
            return "Couldn't find the swift-doc binary."
        }
    }

    var type: ErrorType {
        switch self {
        case .swiftLintNotFound,
             .swiftDocNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the path to the swift-lint binary.
    func swiftLintPath() throws -> AbsolutePath

    /// Returns the path to the swift-doc binary.
    func swiftDocPath() throws -> AbsolutePath
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    private func binariesPaths() throws -> [AbsolutePath] {
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
        return [
            bundlePath,
            bundlePath.parentDirectory,
        ]
    }

    public func swiftLintPath() throws -> AbsolutePath {
        let candidates = try binariesPaths().map { path in
            path.appending(component: Constants.Vendor.swiftLint)
        }

        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.swiftLintNotFound
        }
        return existingPath
    }

    public func swiftDocPath() throws -> AbsolutePath {
        let candidates = try binariesPaths().map { path in
            path.appending(component: Constants.Vendor.swiftDoc)
        }

        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.swiftLintNotFound
        }
        return existingPath
    }
}
