import Foundation
import HTTPTypes
import OpenAPIRuntime
import TuistEnvironment

struct ServerClientActorHeadersMiddleware: ClientMiddleware {
    static let reportOperations: Set<String> = [
        "createBuild", "createBuild (2)", "createTest", "createRun", "createCommandEvent", "createMixBuild", "createGradleBuild",
    ]

    static func actorID(variables: [String: String]) -> String? {
        let value: String?
        if let override = variables["TUIST_ACTOR_ID"] {
            value = override
        } else {
            value = ["USER", "USERNAME", "LOGNAME"].compactMap { variables[$0] }.first { !$0.isEmpty }
        }
        guard let value, !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ (0x21 ... 0x7E).contains($0) })
        else { return nil }
        return value
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if Self.reportOperations.contains(operationID),
           let actorID = Self.actorID(variables: Environment.current.variables),
           let headerName = HTTPField.Name("x-tuist-actor-id"),
           request.headerFields[headerName] == nil
        {
            request.headerFields[headerName] = actorID
        }
        return try await next(request, body, baseURL)
    }
}
