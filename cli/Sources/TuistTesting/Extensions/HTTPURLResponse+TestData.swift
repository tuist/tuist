import Foundation

extension HTTPURLResponse {
    public static func test(
        url: URL = .test(),
        statusCode: Int = 200,
        httpVersion: String? = nil,
        headerFields: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)!
    }
}
