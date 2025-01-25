import Foundation
import Mockable
import Path
import TSCUtility

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
    public init() {}

    /// Shared instance.
    public static var shared: XcodeControlling {
        _shared.value
    }

    // swiftlint:disable:next identifier_name
    static let _shared: ThreadSafe<XcodeControlling> = ThreadSafe(XcodeController())

    /// Cached response of `xcode-select` command
    private let selectedXcode: ThreadSafe<Xcode?> = ThreadSafe(nil)

    /// Returns the selected Xcode. It uses xcode-select to determine
    /// the Xcode that is selected in the environment.
    ///
    /// - Returns: Selected Xcode.
    /// - Throws: An error if it can't be obtained.
    public func selected() async throws -> Xcode {
        if let selectedXcode = selectedXcode.value {
            return selectedXcode
        } else {
            let path = try System.shared.capture(["xcode-select", "-p"]).spm_chomp()
            let value = try await Xcode.read(path: try AbsolutePath(validating: path).parentDirectory.parentDirectory)
            selectedXcode.mutate { $0 = value }
            return value
        }
    }

    public func selectedVersion() async throws -> Version {
        let xcode = try await selected()
        return try Version(versionString: xcode.infoPlist.version, usesLenientParsing: true)
    }
}
