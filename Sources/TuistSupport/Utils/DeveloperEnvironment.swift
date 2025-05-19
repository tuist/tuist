import Foundation
import Path

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
    public static var shared: DeveloperEnvironmenting {
        _shared.value
    }

    // swiftlint:disable identifier_name
    static let _shared: ThreadSafe<DeveloperEnvironmenting> = ThreadSafe(DeveloperEnvironment())

    /// File handler instance.
    let fileHandler: FileHandling

    convenience init() {
        self.init(fileHandler: FileHandler())
    }

    init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler

        derivedDataDirectoryCache = ThrowableCaching<AbsolutePath> {
            if let overrideLocation = try? System.shared.capture([
                "/usr/bin/defaults",
                "read",
                "com.apple.dt.Xcode",
                "IDEDerivedDataPathOverride",
            ]) {
                return try! AbsolutePath(validating: overrideLocation.chomp()) // swiftlint:disable:this force_try
            }

            if let customLocation = try? System.shared.capture([
                "/usr/bin/defaults",
                "read",
                "com.apple.dt.Xcode",
                "IDECustomDerivedDataLocation",
            ]) {
                return try! AbsolutePath(validating: customLocation.chomp()) // swiftlint:disable:this force_try
            }

            // Default location
            return fileHandler.homeDirectory
                .appending(try! RelativePath( // swiftlint:disable:this force_try
                    validating: "Library/Developer/Xcode/DerivedData/"
                ))
        }
    }

    /// https://pewpewthespells.com/blog/xcode_build_locations.html
    private let derivedDataDirectoryCache: ThrowableCaching<AbsolutePath>
    public var derivedDataDirectory: Path.AbsolutePath {
        // swiftlint:disable:next force_try
        try! derivedDataDirectoryCache.value
    }

    public var architecture: MacArchitecture {
        // swiftlint:disable:next force_try
        try! architectureCache.value
    }

    private let architectureCache = ThrowableCaching<MacArchitecture> {
        // swiftlint:disable:next force_try
        let output = try! System.shared.capture(["/usr/bin/uname", "-m"]).chomp()
        return MacArchitecture(rawValue: output)!
    } // swiftlint:enable identifier_name
}
