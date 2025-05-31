internal import Foundation

public struct ManifestLogging: Codable {
    public let message: Message

    init(message: Message) {
        self.message = message
        dumpManifestLoggingIfNeeded(self)
    }

    @discardableResult
    public static func warning(_ message: String) -> ManifestLogging {
        ManifestLogging(message: .warning(message))
    }

    @discardableResult
    public func error(_ message: String)  -> ManifestLogging {
        ManifestLogging(message: .error(message))
    }

    public enum Message: Codable {
        case warning(String)
        case error(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        enum MessageType: String, Codable {
            case warning
            case error
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(MessageType.self, forKey: .type)
            let value = try container.decode(String.self, forKey: .value)

            switch type {
            case .warning:
                self = .warning(value)
            case .error:
                self = .error(value)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .warning(let value):
                try container.encode(MessageType.warning, forKey: .type)
                try container.encode(value, forKey: .value)
            case .error(let value):
                try container.encode(MessageType.error, forKey: .type)
                try container.encode(value, forKey: .value)
            }
        }
    }
}
