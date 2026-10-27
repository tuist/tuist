import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension URLRequest {
    public static func test(url: URL = URL.test()) -> URLRequest {
        URLRequest(url: url)
    }

    public static func test(urlString: String) -> URLRequest {
        URLRequest(url: URL(string: urlString)!)
    }
}
