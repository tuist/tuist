import Foundation
import TuistServer

struct RunnerShellSession {
    let sessionID: Int
    let workflowJobID: Int
    let websocketURL: URL
    let websocketProtocol: String
}

enum RunnerShellSessionServiceError: LocalizedError, Equatable {
    case invalidResponse
    case runnerSessionNotFound(jobRef: String)
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid shell session response."
        case let .runnerSessionNotFound(jobRef):
            return "No live runner shell was found for job \(jobRef). Make sure the job is still running and stopped at an interactive step, then retry."
        case let .requestFailed(statusCode, message):
            return "The server couldn't start a runner shell session (\(statusCode)): \(message)"
        }
    }
}

protocol RunnerShellSessionServicing {
    func create(jobRef: String, serverURL: URL) async throws -> RunnerShellSession
}

struct RunnerShellSessionService: RunnerShellSessionServicing {
    func create(jobRef: String, serverURL: URL) async throws -> RunnerShellSession {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.createRunnerShellSession(query: .init(job_ref: jobRef))

        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(session):
                guard let websocketURL = URL(string: session.websocket_url) else {
                    throw RunnerShellSessionServiceError.invalidResponse
                }

                return RunnerShellSession(
                    sessionID: session.session_id,
                    workflowJobID: session.workflow_job_id,
                    websocketURL: websocketURL,
                    websocketProtocol: session.websocket_protocol
                )
            }
        case .notFound:
            throw RunnerShellSessionServiceError.runnerSessionNotFound(jobRef: jobRef)
        case let .badRequest(badRequest):
            throw RunnerShellSessionServiceError.requestFailed(statusCode: 400, message: errorMessage(badRequest.body))
        case let .unauthorized(unauthorized):
            throw RunnerShellSessionServiceError.requestFailed(statusCode: 401, message: errorMessage(unauthorized.body))
        case let .forbidden(forbidden):
            throw RunnerShellSessionServiceError.requestFailed(statusCode: 403, message: errorMessage(forbidden.body))
        case let .unprocessableContent(unprocessable):
            throw RunnerShellSessionServiceError.requestFailed(statusCode: 422, message: errorMessage(unprocessable.body))
        case let .undocumented(statusCode, _):
            throw RunnerShellSessionServiceError.requestFailed(statusCode: statusCode, message: "unexpected response")
        }
    }

    private func errorMessage(_ body: Operations.createRunnerShellSession.Output.BadRequest.Body) -> String {
        switch body {
        case let .json(error):
            return error.message
        }
    }

    private func errorMessage(_ body: Operations.createRunnerShellSession.Output.Unauthorized.Body) -> String {
        switch body {
        case let .json(error):
            return error.message
        }
    }

    private func errorMessage(_ body: Operations.createRunnerShellSession.Output.Forbidden.Body) -> String {
        switch body {
        case let .json(error):
            return error.message
        }
    }

    private func errorMessage(_ body: Operations.createRunnerShellSession.Output.UnprocessableContent.Body) -> String {
        switch body {
        case let .json(error):
            return error.message
        }
    }
}
