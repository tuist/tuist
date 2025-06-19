import Foundation
import TuistSimulator

extension DestinationType {
    init(_ supportedPlatform: Components.Schemas.PreviewSupportedPlatform) {
        switch supportedPlatform {
        case .ios:
            self = .device(.iOS)
        case .ios_simulator:
            self = .simulator(.iOS)
        case .tvos:
            self = .device(.tvOS)
        case .tvos_simulator:
            self = .simulator(.tvOS)
        case .watchos:
            self = .device(.watchOS)
        case .watchos_simulator:
            self = .simulator(.watchOS)
        case .visionos:
            self = .device(.visionOS)
        case .visionos_simulator:
            self = .simulator(.visionOS)
        case .macos:
            self = .device(.macOS)
        }
    }
}
