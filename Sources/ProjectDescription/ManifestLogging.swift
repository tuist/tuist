internal import Foundation

public struct ManifestLogging: Codable {
    let message: Message

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

    enum Message: Codable {
        case warning(String)
        case error(String)
    }
}
