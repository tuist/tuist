import Foundation
import TuistHTTP
import TuistServer

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct RunnerShellSession: Decodable {
    let sessionID: Int
    let workflowJobID: Int
    let websocketURL: URL
    let websocketProtocol: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case workflowJobID = "workflow_job_id"
        case websocketURL = "websocket_url"
        case websocketProtocol = "websocket_protocol"
    }
}

enum RunnerShellSessionServiceError: LocalizedError, Equatable {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid shell session response."
        case let .requestFailed(statusCode, message):
            return "The server couldn't start a runner shell session (\(statusCode)): \(message)"
        }
    }
}

protocol RunnerShellSessionServicing {
    func create(jobRef: String, serverURL: URL, token: String) async throws -> RunnerShellSession
}

struct RunnerShellSessionService: RunnerShellSessionServicing {
    private let urlSession: URLSession

    init(urlSession: URLSession = .tuistShared) {
        self.urlSession = urlSession
    }

    func create(jobRef: String, serverURL: URL, token: String) async throws -> RunnerShellSession {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/runners/interactive/shell"

        guard let url = components?.url else {
            throw RunnerShellSessionServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["job_ref": jobRef])

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunnerShellSessionServiceError.invalidResponse
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw RunnerShellSessionServiceError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: responseMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        return try JSONDecoder().decode(RunnerShellSession.self, from: data)
    }

    private func responseMessage(_ data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String ?? object["error"] as? String
        else {
            return nil
        }

        return message
    }
}
