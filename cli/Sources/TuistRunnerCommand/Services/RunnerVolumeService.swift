import ArgumentParser
import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

struct RunnerVolumeService {
    let client: Client
    let account: String
    let json: Bool

    static func resolve(_ options: RunnerVolumeOptions) async throws -> RunnerVolumeService {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(options.path)
        let config = try await ConfigLoader().loadConfig(path: directory)
        guard let account = options.account ?? config.fullHandle?.split(separator: "/").first.map(String.init),
              !account.isEmpty
        else { throw ValidationError("Pass --account or configure a project full handle.") }
        let url = try ServerEnvironmentService().url(configServerURL: config.url)
        return RunnerVolumeService(client: .authenticated(serverURL: url), account: account, json: options.json)
    }

    func list(
        name: String?,
        repository: String?,
        sort: RunnerVolumeSort?,
        order: RunnerVolumeSortOrder?,
        pagination: RunnerVolumePagination
    ) async throws {
        let response = try await client.listRunnerVolumes(.init(
            path: .init(account_handle: account),
            query: .init(
                name: name,
                page: pagination.page,
                page_size: pagination.pageSize,
                repository: repository,
                sort_by: sort.flatMap { .init(rawValue: $0.rawValue) },
                sort_order: order.flatMap { .init(rawValue: $0.rawValue) }
            )
        ))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func show(_ id: String) async throws {
        let response = try await client.getRunnerVolume(.init(path: .init(account_handle: account, volume_id: id)))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func jobs(_ id: String, pagination: RunnerVolumePagination) async throws {
        let response = try await client.listRunnerVolumeJobs(.init(
            path: .init(account_handle: account, volume_id: id),
            query: .init(page: pagination.page, page_size: pagination.pageSize)
        ))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func forJob(_ id: Int) async throws {
        let response = try await client.listRunnerJobVolumes(.init(path: .init(account_handle: account, workflow_job_id: id)))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func analytics(_ id: String?, start: Date?, end: Date?) async throws {
        let response = try await client.getRunnerVolumeAnalytics(.init(
            path: .init(account_handle: account), query: .init(end: end, start: start, volume_id: id)
        ))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func clear(_ id: String) async throws {
        let response = try await client.clearRunnerVolume(.init(path: .init(account_handle: account, volume_id: id)))
        switch response {
        case let .ok(value): try render(value.body.json)
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    private func render(_ value: some Codable) throws {
        if json {
            try Noora.current.json(value)
        } else {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            let object = try JSONSerialization.jsonObject(with: data)
            Noora.current.passthrough(TerminalText(stringLiteral: Self.text(object)))
        }
    }

    static func text(_ value: Any, indent: String = "") -> String {
        if let object = value as? [String: Any] {
            return object.keys.sorted().map { key in
                let value = object[key] ?? NSNull()
                if value is [String: Any] || value is [Any] {
                    return "\(indent)\(key):\n\(text(value, indent: indent + "  "))"
                }
                return "\(indent)\(key): \(value is NSNull ? "Not reported" : String(describing: value))"
            }.joined(separator: "\n")
        }
        if let items = value as? [Any] {
            if items.isEmpty { return "\(indent)(none)" }
            return items.map { text($0, indent: indent) }.joined(separator: "\n\(indent)---\n")
        }
        return "\(indent)\(value)"
    }
}
