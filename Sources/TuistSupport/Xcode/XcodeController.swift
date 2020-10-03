import Foundation
import TSCBasic
import TSCUtility

public protocol XcodeControlling {
    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    func selected() throws -> Xcode?

    /// Returns version of the selected Xcode. Uses `selected()` from `XcodeControlling`
    ///
    /// - Returns: `Version` of selected Xcode
    /// - Throws: An error if it can't be obtained
    func selectedVersion() throws -> Version

    /// Returns the path of the derived data if a custom location is defined
    ///
    /// - Returns: `AbsolutePath` of the derived data
    /// - Throws: An error if it can't be obtained
    func derivedDataPath() throws -> AbsolutePath
}

public class XcodeController: XcodeControlling {
    /// Shared instance.
    public static var shared: XcodeControlling = XcodeController()

    /// Cached response of `xcode-select` command
    @Atomic
    private var selectedXcode: Xcode?

    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    public func selected() throws -> Xcode? {
        // Return cached value if available
        if let cached = selectedXcode {
            return cached
        }

        // e.g. /Applications/Xcode.app/Contents/Developer
        guard let path = try? System.shared.capture(["xcode-select", "-p"]).spm_chomp() else {
            return nil
        }

        let xcode = try Xcode.read(path: AbsolutePath(path).parentDirectory.parentDirectory)
        selectedXcode = xcode
        return xcode
    }

    enum XcodeVersionError: FatalError {
        case noXcode
        case noVersion

        var type: ErrorType { .abort }

        var description: String {
            switch self {
            case .noXcode:
                return "Could not find Xcode"
            case .noVersion:
                return "Could not parse XcodeVersion"
            }
        }
    }

    public func selectedVersion() throws -> Version {
        guard let xcode = try selected() else {
            throw XcodeVersionError.noXcode
        }

        guard let version = Version(unformattedString: xcode.infoPlist.version) else {
            throw XcodeVersionError.noXcode
        }

        return version
    }

    public func derivedDataPath() throws -> AbsolutePath {
        guard let path = try? System.shared.capture(["defaults", "read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"]).spm_chomp() else {
            return AbsolutePath("/~/Library/Xcode/DerivedData")
        }

        return AbsolutePath(path)
    }
}
