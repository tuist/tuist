import TuistCore
import TuistSimulator

extension Device {
    func destinationType() throws -> DestinationType {
        switch self {
        case let .device(physicalDevice):
            .device(physicalDevice.platform)
        case let .simulator(simulator):
            try .simulator(simulator.runtime.platform())
        }
    }
}
