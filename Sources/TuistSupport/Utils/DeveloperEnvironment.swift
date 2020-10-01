import Foundation
import TSCBasic

public protocol DeveloperEnvironmenting {
    /// Returns the derived data directory selected in the environment.
    var derivedDataDirectory: AbsolutePath { get }
}

public final class DeveloperEnvironment: DeveloperEnvironmenting {
    /// Shared instance to be used publicly.
    /// Since the environment doesn't change during the execution of Tuist, we can cache
    /// state internally to speed up future access to environment attributes.
    public static let shared: DeveloperEnvironmenting = DeveloperEnvironment()

    /// File handler instance.
    let fileHandler: FileHandling

    private init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// https://pewpewthespells.com/blog/xcode_build_locations.html/// https://pewpewthespells.com/blog/xcode_build_locations.html
    // swiftlint:disable identifier_name
    private var _derivedDataDirectory: AbsolutePath?
    public var derivedDataDirectory: AbsolutePath {
        if let _derivedDataDirectory = _derivedDataDirectory {
            return _derivedDataDirectory
        }
        let location: AbsolutePath
        if let customLocation = try? System.shared.capture("/usr/bin/defaults", "read", "com.apple.dt.Xcode IDECustomDerivedDataLocation") {
            location = AbsolutePath(customLocation.chomp())
        } else {
            // Default location
            location = fileHandler.homeDirectory.appending(RelativePath("Library/Developer/Xcode/DerivedData/"))
        }
        _derivedDataDirectory = location
        return location
    }

    // swiftlint:enable identifier_name
}
