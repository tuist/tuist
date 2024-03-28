import Foundation
import TSCBasic
import TSCUtility

public protocol XcodeControlling {
    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    func selected() throws -> Xcode

    /// Returns version of the selected Xcode. Uses `selected()` from `XcodeControlling`
    ///
    /// - Returns: `Version` of selected Xcode
    /// - Throws: An error if it can't be obtained
    func selectedVersion() throws -> Version
}

public class XcodeController: XcodeControlling {
    public init() {}

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
    public func selected() throws -> Xcode {
        // Return cached value if available
        if let cached = selectedXcode {
            return cached
        }

        // e.g. /Applications/Xcode.app/Contents/Developer
        guard let path = try? System.shared.capture(["xcode-select", "-p"]).spm_chomp() else {
            throw XcodeVersionError.noXcode
        }

        let xcode = try Xcode.read(path: try AbsolutePath(validating: path).parentDirectory.parentDirectory)
        selectedXcode = xcode
        return xcode
    }

    public enum XcodeVersionError: FatalError {
        case noXcode
        case noVersion

        public var type: ErrorType { .abort }

        public var description: String {
            switch self {
            case .noXcode:
                return "Could not find Xcode"
            case .noVersion:
                return "Could not parse XcodeVersion"
            }
        }
    }

    public func selectedVersion() throws -> Version {
        let xcode = try selected()

        guard let version = Version(unformattedString: xcode.infoPlist.version) else {
            throw XcodeVersionError.noXcode
        }

        return version
    }
}
