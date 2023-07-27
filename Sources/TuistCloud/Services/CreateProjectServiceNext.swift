import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol CreateProjectNextServicing {
    func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws
}

public final class CreateProjectNextService: CreateProjectNextServicing {
    public init() {}

    public func createProject(
        name: String,
        organizationName: String?,
        serverURL: URL
    ) async throws {
        let client = Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [
                AuthenticationMiddleware()
            ]
        )
        
        let response = try await client.createProject(
            .init(
                query: .init(name: name)
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(project):
                print(project.name)
            }
        case let .undocumented(statusCode: statusCode, _):
            print("Error", statusCode)
            fatalError()
        }
    }
}
