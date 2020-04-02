import Foundation

public extension URLRequest {
    static func test(url: URL = URL.test()) -> URLRequest {
        URLRequest(url: url)
    }
}
