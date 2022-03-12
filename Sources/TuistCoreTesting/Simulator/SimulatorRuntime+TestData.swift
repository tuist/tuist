import Foundation
import TSCBasic
@testable import TuistCore

extension SimulatorRuntime {
    static func test(
        bundlePath: AbsolutePath =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime",
        buildVersion: String = "17F61",
        runtimeRoot: AbsolutePath =
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot",
        identifier: String = "com.apple.CoreSimulator.SimRuntime.iOS-13-5",
        version: SimulatorRuntimeVersion = "13.5",
        isAvailable: Bool = true,
        name: String = "iOS 13.5"
    ) -> SimulatorRuntime {
        SimulatorRuntime(
            bundlePath: bundlePath,
            buildVersion: buildVersion,
            runtimeRoot: runtimeRoot,
            identifier: identifier,
            version: version,
            isAvailable: isAvailable,
            name: name
        )
    }
}
