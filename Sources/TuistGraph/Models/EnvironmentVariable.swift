import Foundation

public struct EnvironmentVariable: Equatable, Codable, Hashable {
    public let key: String
    public let value: String
    public let isEnabled: Bool

    public init(key: String, value: String, isEnabled: Bool) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
