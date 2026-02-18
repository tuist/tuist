import Foundation

public struct AndroidDevice: Equatable, Sendable, CustomStringConvertible {
    public let id: String
    public let name: String
    public let isEmulator: Bool

    public init(id: String, name: String, isEmulator: Bool) {
        self.id = id
        self.name = name
        self.isEmulator = isEmulator
    }

    public var description: String {
        if isEmulator {
            return "\(name) (emulator: \(id))"
        } else {
            return "\(name) (device: \(id))"
        }
    }
}
