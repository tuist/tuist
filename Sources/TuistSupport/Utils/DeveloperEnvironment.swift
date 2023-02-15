import Foundation
import TSCBasic

public protocol DeveloperEnvironmenting {
    /// Returns the derived data directory selected in the environment.
    var derivedDataDirectory: AbsolutePath { get }

    /// Returns the system's architecture.
    var architecture: MacArchitecture { get }
}

public final class DeveloperEnvironment: DeveloperEnvironmenting {
    /// Shared instance to be used publicly.
    /// Since the environment doesn't change during the execution of Tuist, we can cache
    /// state internally to speed up future access to environment attributes.
    public internal(set) static var shared: DeveloperEnvironmenting = DeveloperEnvironment()

    /// File handler instance.
    let fileHandler: FileHandling

    convenience init() {
        self.init(fileHandler: FileHandler())
    }

    private init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler
    }

    /// https://pewpewthespells.com/blog/xcode_build_locations.html/// https://pewpewthespells.com/blog/xcode_build_locations.html
    // swiftlint:disable identifier_name
    @Atomic private var _derivedDataDirectory: AbsolutePath?
    public var derivedDataDirectory: AbsolutePath {
        if let _derivedDataDirectory = _derivedDataDirectory {
            return _derivedDataDirectory
        }
        let location: AbsolutePath
        if let customLocation = try? System.shared.capture([
            "/usr/bin/defaults",
            "read",
            "com.apple.dt.Xcode IDECustomDerivedDataLocation",
        ]) {
            location = try! AbsolutePath(validating: customLocation.chomp()) // swiftlint:disable:this force_try
        } else {
            // Default location
            location = fileHandler.homeDirectory.appending(RelativePath("Library/Developer/Xcode/DerivedData/"))
        }
        _derivedDataDirectory = location
        return location
    }

    @Atomic private var _architecture: MacArchitecture?
    public var architecture: MacArchitecture {
        if let _architecture = _architecture {
            return _architecture
        }
        // swiftlint:disable:next force_try
        let output = try! System.shared.capture(["/usr/bin/uname", "-m"]).chomp()
        _architecture = MacArchitecture(rawValue: output)
        return _architecture!
    }
}
