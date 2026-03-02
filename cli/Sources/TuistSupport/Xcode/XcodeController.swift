import Foundation
import Mockable
import Path
import TSCUtility
import TuistThreadSafe

@Mockable
public protocol XcodeControlling: Sendable {
    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    func selected() async throws -> Xcode

    /// Returns version of the selected Xcode. Uses `selected()` from `XcodeControlling`
    ///
    /// - Returns: `Version` of selected Xcode
    /// - Throws: An error if it can't be obtained
    func selectedVersion() async throws -> Version
}

public final class XcodeController: XcodeControlling, @unchecked Sendable {
    @TaskLocal public static var current: XcodeControlling = XcodeController()

    public init() {}

    /// Cached response of `xcode-select` command
    private let selectedXcode: ThreadSafe<Xcode?> = ThreadSafe(nil)

    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    /// If `DEVELOPER_DIR` is set, it takes precedence over what
    /// xcode-select returns.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    public func selected() async throws -> Xcode {
        if let selectedXcode = selectedXcode.value {
            return selectedXcode
        } else {
            let xcodePath: Xcode.PathSource
            if let environmentValue = Environment.current.variables["DEVELOPER_DIR"] {
                // It's valid to either point DEVELOPER_DIR directly to Xcode.app/ - or
                // to the developer content directory. See man xcode-select # ENVIRONMENT
                var path = try AbsolutePath(validating: environmentValue)
                if path.pathString.hasSuffix("Contents/Developer") {
                    path = path.parentDirectory.parentDirectory
                }
                xcodePath = .environment(path)
            } else {
                let path = try System.shared.capture(["xcode-select", "-p"]).spm_chomp()
                xcodePath = try .xcodeSelect(AbsolutePath(validating: path).parentDirectory.parentDirectory)
            }

            Logger.current.debug("Using Xcode at \(xcodePath)")

            let value = try await Xcode.read(source: xcodePath)
            selectedXcode.mutate { $0 = value }
            return value
        }
    }

    public func selectedVersion() async throws -> Version {
        let xcode = try await selected()
        return try Version(versionString: xcode.infoPlist.version, usesLenientParsing: true)
    }
}
