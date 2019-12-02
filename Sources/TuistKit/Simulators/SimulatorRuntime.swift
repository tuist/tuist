import Foundation

/// Enum that represents all different runtimes that are available for simulators.
enum SimulatorRuntime: CustomStringConvertible {
    /// iOS runtime
    case iOS(SimulatorRuntimeVersion)
    
    /// watchOS runtime
    case watchOS(SimulatorRuntimeVersion)
    
    /// tvOS runtime
    case tvOS(SimulatorRuntimeVersion)
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        switch self {
        case .iOS(let version):
            return "iOS \(version) runtime"
        case .tvOS(let version):
            return "tvOS \(version) runtime"
        case .watchOS(let version):
            return "watchOS \(version) runtime"
        }
    }
    
}
