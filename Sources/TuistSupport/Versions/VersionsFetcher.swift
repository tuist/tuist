import Foundation

public protocol VersionsFetching {
    /// Reads the versions of some system utilities that
    /// Tuist depends on and returns them grouped in an
    /// instance of Versions.
    func fetch() throws -> Versions
}

public final class VersionsFetcher: VersionsFetching {
    /// Xcode controller.
    fileprivate let xcodeController: XcodeControlling

    /// System instance.
    fileprivate let system: Systeming

    public convenience init() {
        self.init(xcodeController: XcodeController.shared,
                  system: System.shared)
    }

    internal init(xcodeController: XcodeControlling,
                  system: Systeming) {
        self.xcodeController = xcodeController
        self.system = system
    }

    public func fetch() throws -> Versions {
        let xcodeVersion = try xcodeController.selectedVersion()
        let swiftVersion = try system.swiftVersion()
        return Versions(xcode: xcodeVersion, swift: swiftVersion)
    }
}
