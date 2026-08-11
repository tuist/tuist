import Foundation

public enum AuthenticationDiagnosticEvent: Sendable {
    case authenticationStateInitialized(state: String)
    case credentialsChanged(
        hasCredentials: Bool,
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?
    )
    case credentialsStoredAfterSignIn(
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?
    )
    case userInitiatedSignOut
    case tokenStatusEvaluated(
        status: String,
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?,
        coordinationStoreIdentifier: String,
        credentialsStoreIdentifier: String
    )
    case tokenRefreshStarted(
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date,
        coordinationStoreIdentifier: String,
        credentialsStoreIdentifier: String
    )
    case tokenRefreshSucceeded(
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?
    )
    case tokenRefreshFailed(errorType: String)
    case unauthorizedRefreshHandled(credentialsChangedDuringRefresh: Bool)
    case requestFailed(errorType: String, underlyingErrorType: String?)
}

public final class AuthenticationDiagnostics: @unchecked Sendable {
    public static let shared = AuthenticationDiagnostics()

    private struct Entry {
        let date: Date
        let event: AuthenticationDiagnosticEvent
    }

    private let lock = NSLock()
    private let maximumEventCount: Int
    private var entries: [Entry] = []
    private var objectLabels: [ObjectIdentifier: String] = [:]

    public init(maximumEventCount: Int = 200) {
        precondition(maximumEventCount > 0)
        self.maximumEventCount = maximumEventCount
    }

    public func record(
        _ event: AuthenticationDiagnosticEvent,
        at date: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        entries.append(Entry(date: date, event: event))
        if entries.count > maximumEventCount {
            entries.removeFirst(entries.count - maximumEventCount)
        }
    }

    public func label(for object: AnyObject) -> String {
        lock.lock()
        defer { lock.unlock() }

        let identifier = ObjectIdentifier(object)
        if let label = objectLabels[identifier] {
            return label
        }

        let label = "store-\(objectLabels.count + 1)"
        objectLabels[identifier] = label
        return label
    }

    public func report(
        appVersion: String,
        appBuild: String,
        operatingSystemVersion: String,
        generatedAt: Date = Date()
    ) -> String {
        lock.lock()
        let entries = entries
        lock.unlock()

        let lines = entries.map { entry in
            "\(Self.format(entry.date)) | \(Self.describe(entry.event))"
        }

        return ([
            "Tuist authentication diagnostics",
            "Generated: \(Self.format(generatedAt))",
            "App version: \(appVersion) (\(appBuild))",
            "Operating system: \(operatingSystemVersion)",
            "",
            "This report never includes access or refresh token values.",
            "",
            "Events:",
        ] + (lines.isEmpty ? ["No authentication events recorded."] : lines))
            .joined(separator: "\n")
    }

    public func currentProcessReport(generatedAt: Date = Date()) -> String {
        report(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            generatedAt: generatedAt
        )
    }

    private static func describe(_ event: AuthenticationDiagnosticEvent) -> String {
        switch event {
        case let .authenticationStateInitialized(state):
            return "authentication_state_initialized state=\(state)"
        case let .credentialsChanged(hasCredentials, accessTokenExpiresAt, refreshTokenExpiresAt):
            return "credentials_changed has_credentials=\(hasCredentials) "
                + expirationDescription(
                    accessTokenExpiresAt: accessTokenExpiresAt,
                    refreshTokenExpiresAt: refreshTokenExpiresAt
                )
        case let .credentialsStoredAfterSignIn(accessTokenExpiresAt, refreshTokenExpiresAt):
            return "credentials_stored_after_sign_in "
                + expirationDescription(
                    accessTokenExpiresAt: accessTokenExpiresAt,
                    refreshTokenExpiresAt: refreshTokenExpiresAt
                )
        case .userInitiatedSignOut:
            return "user_initiated_sign_out"
        case let .tokenStatusEvaluated(
            status,
            accessTokenExpiresAt,
            refreshTokenExpiresAt,
            coordinationStoreIdentifier,
            credentialsStoreIdentifier
        ):
            return tokenStatusDescription(
                status: status,
                accessTokenExpiresAt: accessTokenExpiresAt,
                refreshTokenExpiresAt: refreshTokenExpiresAt,
                coordinationStoreIdentifier: coordinationStoreIdentifier,
                credentialsStoreIdentifier: credentialsStoreIdentifier
            )
        case let .tokenRefreshStarted(
            accessTokenExpiresAt,
            refreshTokenExpiresAt,
            coordinationStoreIdentifier,
            credentialsStoreIdentifier
        ):
            return tokenRefreshStartedDescription(
                accessTokenExpiresAt: accessTokenExpiresAt,
                refreshTokenExpiresAt: refreshTokenExpiresAt,
                coordinationStoreIdentifier: coordinationStoreIdentifier,
                credentialsStoreIdentifier: credentialsStoreIdentifier
            )
        case .tokenRefreshSucceeded, .tokenRefreshFailed, .unauthorizedRefreshHandled, .requestFailed:
            return describeRefreshOutcome(event)
        }
    }

    private static func describeRefreshOutcome(_ event: AuthenticationDiagnosticEvent) -> String {
        switch event {
        case let .tokenRefreshSucceeded(accessTokenExpiresAt, refreshTokenExpiresAt):
            return "token_refresh_succeeded "
                + expirationDescription(
                    accessTokenExpiresAt: accessTokenExpiresAt,
                    refreshTokenExpiresAt: refreshTokenExpiresAt
                )
        case let .tokenRefreshFailed(errorType):
            return "token_refresh_failed error_type=\(errorType)"
        case let .unauthorizedRefreshHandled(credentialsChangedDuringRefresh):
            return "unauthorized_refresh_handled credentials_changed_during_refresh=\(credentialsChangedDuringRefresh)"
        case let .requestFailed(errorType, underlyingErrorType):
            return "request_failed error_type=\(errorType) underlying_error_type=\(underlyingErrorType ?? "none")"
        default:
            preconditionFailure("Unexpected authentication diagnostic event")
        }
    }

    private static func tokenStatusDescription(
        status: String,
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?,
        coordinationStoreIdentifier: String,
        credentialsStoreIdentifier: String
    ) -> String {
        "token_status_evaluated status=\(status) "
            + expirationDescription(
                accessTokenExpiresAt: accessTokenExpiresAt,
                refreshTokenExpiresAt: refreshTokenExpiresAt
            )
            + " coordination_store=\(coordinationStoreIdentifier)"
            + " credentials_store=\(credentialsStoreIdentifier)"
    }

    private static func tokenRefreshStartedDescription(
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date,
        coordinationStoreIdentifier: String,
        credentialsStoreIdentifier: String
    ) -> String {
        "token_refresh_started "
            + expirationDescription(
                accessTokenExpiresAt: accessTokenExpiresAt,
                refreshTokenExpiresAt: refreshTokenExpiresAt
            )
            + " coordination_store=\(coordinationStoreIdentifier)"
            + " credentials_store=\(credentialsStoreIdentifier)"
    }

    private static func expirationDescription(
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?
    ) -> String {
        "access_token_expires_at=\(accessTokenExpiresAt.map(format) ?? "unknown") "
            + "refresh_token_expires_at=\(refreshTokenExpiresAt.map(format) ?? "unknown")"
    }

    private static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
