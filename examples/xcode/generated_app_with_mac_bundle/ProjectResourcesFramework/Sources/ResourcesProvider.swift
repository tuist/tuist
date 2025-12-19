import Foundation

public enum ResourcesProvider {
    public static func greeting() -> String {
        let url = Bundle.module.url(forResource: "greeting", withExtension: "txt")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
