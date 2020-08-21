import Foundation
import TSCBasic

/// It represents a runtime that is available in the system. The list of available runtimes is obtained
/// using Xcode's simctl cli tool.
struct SimulatorRuntime: Decodable, Hashable, CustomStringConvertible {
    /// Runtime bundle path (e.g. /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime)
    let bundlePath: AbsolutePath

    /// Runtime build version (e.g. 17F61)
    let buildVersion: String

    /// Runtime root (e.g. /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes\/iOS.simruntime\Contents/Resources/RuntimeRoot)
    let runtimeRoot: AbsolutePath

    /// Runtime identifier (e.g. com.apple.CoreSimulator.SimRuntime.iOS-13-5)
    let identifier: String

    /// Runtime version (e.g. 13.5)
    let version: SimulatorRuntimeVersion

    // True if the runtime is available.
    let isAvailable: Bool

    // Name of the runtime (e.g. iOS 13.5)
    let name: String

    init(bundlePath: AbsolutePath,
         buildVersion: String,
         runtimeRoot: AbsolutePath,
         identifier: String,
         version: SimulatorRuntimeVersion,
         isAvailable: Bool,
         name: String)
    {
        self.bundlePath = bundlePath
        self.buildVersion = buildVersion
        self.runtimeRoot = runtimeRoot
        self.identifier = identifier
        self.version = version
        self.isAvailable = isAvailable
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case bundlePath
        case buildVersion = "buildversion"
        case runtimeRoot
        case identifier
        case version
        case isAvailable
        case name
    }

    var description: String {
        name
    }
}
