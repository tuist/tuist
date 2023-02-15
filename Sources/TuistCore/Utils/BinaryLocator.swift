import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case xcbeautifyNotFound

    var description: String {
        switch self {
        case .xcbeautifyNotFound:
            return "Couldn't find the xcbeautify binary."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcbeautifyNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the path to the xcbeautify binary.
    func xcbeautifyPath() throws -> AbsolutePath
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    private func binariesPaths() throws -> [AbsolutePath] {
        #if DEBUG
            // Used only for debug purposes
            let bundlePath = try AbsolutePath(validating: #file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(RelativePath("projects/tuist/vendor"))
        #else
            let bundlePath = try AbsolutePath(validating: Bundle(for: BinaryLocator.self).bundleURL.path)
        #endif
        return [
            bundlePath,
            bundlePath.parentDirectory,
            bundlePath.appending(RelativePath("vendor")),
        ]
    }

    public func xcbeautifyPath() throws -> AbsolutePath {
        let candidates = try binariesPaths().map { path in
            path.appending(components: Constants.Vendor.xcbeautify, Constants.Vendor.xcbeautify)
        }

        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.xcbeautifyNotFound
        }
        return existingPath
    }
}
