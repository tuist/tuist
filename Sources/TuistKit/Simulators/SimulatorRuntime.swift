import Basic
import Foundation
import TuistCore
import TuistSupport

enum SimulatorRuntimeError: FatalError {
    /// Thrown when the platform cant't be recognized from the runtime name.
    case unsupportedPlatform(String)

    var description: String {
        switch self {
        case let .unsupportedPlatform(runtime):
            return "Couldn't recognize the platform from runtime \(runtime)"
        }
    }

    var type: ErrorType {
        switch self {
        case .unsupportedPlatform: return .bug
        }
    }
}

/// Enum that represents all different runtimes that are available for simulators.
struct SimulatorRuntime: CustomStringConvertible, Decodable {
    /// Simulator platform.
    let platform: Platform

    /// Runtime version.
    let version: SimulatorRuntimeVersion

    /// Bundle path.
    let bundlePath: AbsolutePath

    /// Whether the runtime is available or not.
    let isAvailable: Bool

    /// Runtime identifier.
    let identifier: String

    /// Runtime buidl version.
    let buildVersion: String

    /// Runtime description.
    var description: String {
        return "\(platform.caseValue) \(version) runtime"
    }

    enum CodingKeys: String, CodingKey {
        case version
        case bundlePath
        case isAvailable
        case name
        case identifier
        case buildVersion = "buildversion"
    }

    // MARK: - Constructors

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(SimulatorRuntimeVersion.self, forKey: .version)
        bundlePath = try container.decode(AbsolutePath.self, forKey: .bundlePath)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        identifier = try container.decode(String.self, forKey: .identifier)
        buildVersion = try container.decode(String.self, forKey: .buildVersion)
        let name = try container.decode(String.self, forKey: .name)
        platform = try SimulatorRuntime.platformFrom(name: name)
    }

    // MARK: - Fileprivate

    fileprivate static func platformFrom(name: String) throws -> Platform {
        if let platform = Platform.allCases.first(where: { name.contains($0.caseValue) }) {
            return platform
        }
        throw SimulatorRuntimeError.unsupportedPlatform(name)
    }
}
