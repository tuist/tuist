import CryptoKit
import Foundation
import Mockable

@Mockable
public protocol MachineEnvironmentRetrieving: Sendable {
    var clientId: String { get }
    var macOSVersion: String { get }
    var hardwareName: String { get }
    var isCI: Bool { get }
}

/// `MachineEnvironment` is a data structure that contains information about the machine executing Tuist
public final class MachineEnvironment: MachineEnvironmentRetrieving {
    public static let shared = MachineEnvironment()
    private init() {}

    /// `clientId` is a unique anonymous hash that identifies the machine running Tuist
    public let clientId: String = {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(platformExpert) }
        guard platformExpert != 0 else {
            fatalError("Couldn't obtain the platform expert")
        }
        let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as! String // swiftlint:disable:this force_cast
        return Insecure.MD5.hash(data: uuid.data(using: .utf8)!)
            .compactMap { String(format: "%02x", $0) }.joined()
    }()

    /// The `macOSVersion` of the machine running Tuist, in the format major.minor.path, e.g: "10.15.7"
    public let macOSVersion = """
    \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\
    \(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\
    \(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)
    """

    /// `hardwareName` is the name of the architecture of the machine running Tuist, e.g: "arm64" or "x86_64"
    public let hardwareName = ProcessInfo.processInfo.machineHardwareName

    /// Indicates whether Tuist is running in Continuous Integration (CI) environment
    public var isCI: Bool {
        CIChecker().isCI()
    }
}

extension ProcessInfo {
    /// Returns a `String` representing the machine hardware name
    var machineHardwareName: String {
        var sysinfo = utsname()
        let result = uname(&sysinfo)
        guard result == EXIT_SUCCESS else { fatalError("uname result is \(result)") }
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        return String(bytes: data, encoding: .ascii)!.trimmingCharacters(in: .controlCharacters)
    }
}
