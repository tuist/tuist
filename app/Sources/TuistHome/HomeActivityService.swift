import Foundation
import TuistServer

public protocol HomeActivityFetching: Sendable {
    func fetch(_ kind: HomeActivityKind, fullHandle: String, serverURL: URL) async throws -> [HomeActivityItem]
}

public struct HomeActivityService: HomeActivityFetching {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        makeClient = { Client.authenticated(serverURL: $0) }
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func fetch(_ kind: HomeActivityKind, fullHandle: String, serverURL: URL) async throws -> [HomeActivityItem] {
        let handles = fullHandle.split(separator: "/").map(String.init)
        guard handles.count == 2 else { throw HomeActivityError.invalidResponse }
        let client = makeClient(serverURL)
        let page: Components.Schemas.HomeActivity
        switch kind {
        case .buildFailures:
            let response = try await client.getHomeBuildFailures(path: .init(
                account_handle: handles[0], project_handle: handles[1]
            ))
            switch response {
            case let .ok(ok): page = try ok.body.json
            case .unprocessableContent: throw HomeActivityError.unsupported
            case .forbidden: throw HomeActivityError.forbidden
            default: throw HomeActivityError.unavailable
            }
        case .testFailures:
            let response = try await client.getHomeTestFailures(path: .init(
                account_handle: handles[0], project_handle: handles[1]
            ))
            switch response {
            case let .ok(ok): page = try ok.body.json
            case .unprocessableContent: throw HomeActivityError.unsupported
            case .forbidden: throw HomeActivityError.forbidden
            default: throw HomeActivityError.unavailable
            }
        case .flakyTests:
            let response = try await client.getHomeFlakyTests(path: .init(
                account_handle: handles[0], project_handle: handles[1]
            ))
            switch response {
            case let .ok(ok): page = try ok.body.json
            case .unprocessableContent: throw HomeActivityError.unsupported
            case .forbidden: throw HomeActivityError.forbidden
            default: throw HomeActivityError.unavailable
            }
        }
        return try page.items.prefix(3).map { item in
            guard item.occurred_at > 0, item.occurred_at < 253_402_300_800 else { throw HomeActivityError.invalidResponse }
            return HomeActivityItem(
                id: item.id,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.title : item.title,
                subtitle: item.subtitle,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(item.occurred_at)),
                url: try Self.dashboardURL(item.url, fullHandle: fullHandle, serverURL: serverURL)
            )
        }
    }

    static func dashboardURL(_ path: String, fullHandle: String, serverURL: URL) throws -> URL {
        guard let components = URLComponents(string: path), components.scheme == nil, components.host == nil,
              components.query == nil, components.fragment == nil
        else { throw HomeActivityError.invalidResponse }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 4, Array(parts.prefix(2)) == fullHandle.split(separator: "/").map(String.init),
              !parts.contains(".."), !parts.contains(".")
        else { throw HomeActivityError.invalidResponse }
        return parts.reduce(serverURL) { $0.appendingPathComponent($1) }
    }
}

enum HomeActivityError: LocalizedError, Equatable {
    case invalidResponse
    case unsupported
    case forbidden
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned activity that couldn't be displayed."
        case .unsupported: "This activity isn't available for this project's build system yet."
        case .forbidden: "You don't have permission to view this activity."
        case .unavailable: "Activity is unavailable. The server may need an update, or the request may have failed."
        }
    }
}
