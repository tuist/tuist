import TuistCore

extension Device {
    var destinationType: DestinationType? {
        switch self {
        case let .device(physicalDevice):
            .device(physicalDevice.platform)
        case let .simulator(simulator):
            simulator.runtime.platform.map(DestinationType.simulator)
        }
    }
}
