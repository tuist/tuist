import Foundation

/// A `Plugin` manifest allows for defining extensions to Tuist.
public struct Plugin: Codable, Equatable {
    /// The type of `Plugin`.
    public enum PluginType: Codable, Equatable {
        /// A `Plugin` which can be used to extend functionality wherever `ProjectDescription` is available.
        case helper(name: String)
    }

    /// The type of `Plugin`.
    public let pluginType: PluginType

    /// A plugin for extending `ProjectDescription`
    /// - Parameter name: The name of `Plugin`.
    public static func helper(name: String) -> Self {
        .init(type: .helper(name: name))
    }

    /// Creates a `Plugin`.
    /// - Parameter type: The type of `Plugin`.
    init(type: PluginType) {
        pluginType = type
        dumpIfNeeded(self)
    }
}

// MARK: - Codable

extension Plugin.PluginType {
    enum CodingKeys: CodingKey {
        case plugin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = container.allKeys.first

        switch key {
        case .plugin:
            let name = try container.decode(String.self, forKey: .plugin)
            self = .helper(name: name)
        case .none:
            throw DecodingError.dataCorruptedError(forKey: .plugin, in: container, debugDescription: "Invalid key")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .helper(name):
            try container.encode(name, forKey: .plugin)
        }
    }
}
