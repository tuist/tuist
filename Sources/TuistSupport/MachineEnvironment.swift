import Foundation
import Checksum

public protocol MachineEnvironmentRetrieving {
    var clientId: String { get }
    var macOSVersion: String { get }
    var swiftVersion: String { get }
    var hardwareName: String { get }
}

/// `MachineEnvironment` is a data structure that contains information about the machine executing Tuist
public class MachineEnvironment: MachineEnvironmentRetrieving {
    public static let shared = MachineEnvironment()
    private init() { }

    /// `clientId` is a unique anonymous hash that identifies the machine running Tuist
    public let clientId = (Host.current().name?.checksum(algorithm: .md5)) ?? "unknown"

    /// The `macOSVersion` of the machine running Tuist, in the format major.minor.path, e.g: "10.15.7"
    public let macOSVersion = "\( ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\( ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)"

    /// The `swiftVersion` of the machine running Tuist
    public let swiftVersion = (try? System.shared.capture("/usr/bin/xcrun", "swift", "-version").components(separatedBy: "Swift version ").last?.components(separatedBy: " ").first) ?? "unknown"

    /// `hardwareName` is the name of the architecture of the machine running Tuist, e.g: "arm64" or "x86_64"
    public let hardwareName = ProcessInfo.processInfo.machineHardwareName 
}

extension ProcessInfo {
        /// Returns a `String` representing the machine hardware name or "unknown" if there was an error invoking `uname(_:)` or decoding the response.
        var machineHardwareName: String {
                var sysinfo = utsname()
                let result = uname(&sysinfo)
                guard result == EXIT_SUCCESS else { return "unknown" }
                let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
                guard let identifier = String(bytes: data, encoding: .ascii) else { return "unknown" }
                return identifier.trimmingCharacters(in: .controlCharacters)
        }
}
