import Foundation

public extension URLRequest {
    static func test(url: URL = URL.test()) -> URLRequest {
        URLRequest(url: url)
    }

    static func test(urlString: String) -> URLRequest {
        URLRequest(url: URL(string: urlString)!)
    }
}
