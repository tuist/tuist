import Foundation

public struct StaticFrameworkType {
    public let name: String
    public init(name: String) {
        self.name = name
    }

    public static var typeIdentifier: String {
        "\(ObjectIdentifier(StaticFrameworkType.self))"
    }
}
