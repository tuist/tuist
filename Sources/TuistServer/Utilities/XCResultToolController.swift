import Mockable
import Path
import TuistSupport

@Mockable
protocol XCResultToolControlling {
    func resultBundleObject(_ path: AbsolutePath) throws -> String
    func resultBundleObject(_ path: AbsolutePath, id: String) throws -> String
}

final class XCResultToolController: XCResultToolControlling {
    private let system: Systeming

    init(
        system: Systeming = System.shared
    ) {
        self.system = system
    }

    func resultBundleObject(_ path: AbsolutePath) throws -> String {
        try system.capture(
            ["/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format", "json"]
        )
    }

    func resultBundleObject(_ path: AbsolutePath, id: String) throws -> String {
        try system.capture(
            ["/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id, "--format", "json"]
        )
    }
}
