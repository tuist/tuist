import Foundation

public struct LocalSwiftPackage {
    public static let greeting: String = {
        guard let url = Bundle.module.url(forResource: "greeting", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    public init() {}
}
