import Foundation

public struct AndroidDevice: Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
    public enum DeviceType: Equatable, Hashable, Sendable, Codable {
        case emulator
        case device
    }

    public let id: String
    public let name: String
    public let type: DeviceType

    public init(id: String, name: String, type: DeviceType) {
        self.id = id
        self.name = name
        self.type = type
    }

    public var description: String {
        switch type {
        case .emulator:
            return "\(name) (emulator: \(id))"
        case .device:
            return "\(name) (device: \(id))"
        }
    }
}
