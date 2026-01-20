import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

enum AccountTokensCreateCommandServiceError: LocalizedError, Equatable {
    case invalidExpiresDuration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidExpiresDuration(duration):
            return "Invalid expires duration '\(duration)'. Use format like '30d' (days), '6m' (months), or '1y' (years)."
        }
    }
}

struct AccountTokensCreateCommandService {
    private let createAccountTokenService: CreateAccountTokenServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        createAccountTokenService: CreateAccountTokenServicing = CreateAccountTokenService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createAccountTokenService = createAccountTokenService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        accountHandle: String,
        scopes: [Components.Schemas.CreateAccountToken.scopesPayloadPayload],
        name: String,
        expires: String?,
        projects: [String]?,
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let expiresAt: Date?
        if let expires {
            expiresAt = try parseExpiresDuration(expires)
        } else {
            expiresAt = nil
        }

        let result = try await createAccountTokenService.createAccountToken(
            accountHandle: accountHandle,
            scopes: scopes,
            name: name,
            expiresAt: expiresAt,
            projectHandles: projects,
            serverURL: serverURL
        )

        Noora.current.info(.init(stringLiteral: result.token))
    }

    private func parseExpiresDuration(_ duration: String) throws -> Date {
        let pattern = #"^(\d+)([dmy])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: duration, range: NSRange(duration.startIndex..., in: duration)),
              let valueRange = Range(match.range(at: 1), in: duration),
              let unitRange = Range(match.range(at: 2), in: duration),
              let value = Int(duration[valueRange])
        else {
            throw AccountTokensCreateCommandServiceError.invalidExpiresDuration(duration)
        }

        let unit = duration[unitRange].lowercased()
        let calendar = Calendar.current
        let now = Date()

        let component: Calendar.Component
        switch unit {
        case "d":
            component = .day
        case "m":
            component = .month
        case "y":
            component = .year
        default:
            throw AccountTokensCreateCommandServiceError.invalidExpiresDuration(duration)
        }

        guard let expiresAt = calendar.date(byAdding: component, value: value, to: now) else {
            throw AccountTokensCreateCommandServiceError.invalidExpiresDuration(duration)
        }

        return expiresAt
    }
}
