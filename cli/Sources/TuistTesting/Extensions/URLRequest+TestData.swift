import Foundation

extension URLRequest {
    public static func test(url: URL = URL.test()) -> URLRequest {
        URLRequest(url: url)
    }

    public static func test(urlString: String) -> URLRequest {
        URLRequest(url: URL(string: urlString)!)
    }
}
