import Foundation

public enum AssetsMessage {
    public static var message: String? {
        Bundle.module.url(forResource: "message", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
