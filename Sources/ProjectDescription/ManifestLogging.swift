internal import Foundation

public final class ManifestLogging {
    @discardableResult
    public static func warning(_ message: String) -> ManifestLogging.Log {
        let log = Log.warning(message)
        dumpManifestLogIfNeeded(log)
        return log
    }

    @discardableResult
    public static func error(_ message: String)  -> ManifestLogging.Log {
        let log = Log.error(message)
        dumpManifestLogIfNeeded(log)
        return log
    }

    public enum Log: Codable {
        case warning(String)
        case error(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        enum LogType: String, Codable {
            case warning
            case error
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(LogType.self, forKey: .type)
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
                try container.encode(LogType.warning, forKey: .type)
                try container.encode(value, forKey: .value)
            case .error(let value):
                try container.encode(LogType.error, forKey: .type)
                try container.encode(value, forKey: .value)
            }
        }
    }
}
