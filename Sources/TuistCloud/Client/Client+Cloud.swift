import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

extension Client {
    static func cloud(serverURL: URL) -> Client {
        .init(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [
                AuthenticationMiddleware(),
            ]
        )
    }
}
