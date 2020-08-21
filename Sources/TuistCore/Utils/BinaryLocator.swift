import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case swiftDocNotFound

    var description: String {
        switch self {
        case .swiftDocNotFound:
            return "Couldn't find the swift-doc binary."
        }
    }

    var type: ErrorType {
        switch self {
        case .swiftDocNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the path to the swift-doc binary.
    func swiftDocPath() throws -> AbsolutePath
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    public func swiftDocPath() throws -> AbsolutePath {
        #if DEBUG
            // Used only for debug purposes to find templates in your tuist working directory
            // `bundlePath` points to tuist/Templates
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
            path.appending(component: Constants.Vendor.swiftDoc)
        }
        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.swiftDocNotFound
        }
        return existingPath
    }
}
