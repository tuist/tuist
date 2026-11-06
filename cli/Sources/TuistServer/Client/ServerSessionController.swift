import Foundation
import Mockable
import TuistOpener
import TuistUniqueIDGenerator

#if canImport(TuistSupport)
    import TuistAlert
    import TuistSupport
#endif

/// Type of device code used for authentication.
public enum DeviceCodeType {
    case cli
    case app

    var apiValue: String {
        switch self {
        case .app:
            "app"
        case .cli:
            "cli"
        }
    }
}

public enum ServerSessionControllerError: Equatable, LocalizedError {
    case unauthenticated
    case deviceCodeExpired

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "You are not logged in. Run 'tuist auth login'."
        case .deviceCodeExpired:
            "The sign-in code expired before it was approved. Run 'tuist auth login' again."
        }
    }
}

@Mockable
public protocol ServerSessionControlling {
    /// It authenticates the user for the server with the given URL.
    /// - Parameters:
    ///     - serverURL: Server URL.
    ///     - deviceCodeType: Type of device origin used for authentication.
    ///     - onUserCode: Triggered with the code the user has to enter in the browser, before the browser opens.
    ///     - onOpeningBrowser: Triggered when we begin opening the browser at the given authentication url.
    ///     - onAuthWaitBegin: Custom callback when we started waiting for the authentication to finish in the browser.
    func authenticate(
        serverURL: URL,
        deviceCodeType: DeviceCodeType,
        onUserCode: @escaping (String) async -> Void,
        onOpeningBrowser: @escaping (URL) async -> Void,
        onAuthWaitBegin: @escaping () async -> Void
    ) async throws

    /// - Returns: Account handle for the signed-in user for the server with the given URL. Returns nil if no user is logged in.
    func whoami(serverURL: URL) async throws -> String?

    /// - Returns: Account handle for the signed-in user for the server with the given URL. Throws if no user is logged in.
    func authenticatedHandle(serverURL: URL) async throws -> String

    /// Removes the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func logout(serverURL: URL) async throws
}

public struct ServerSessionController: ServerSessionControlling {
    static let port: UInt16 = 4545

    private let getAuthTokenService: GetAuthTokenServicing
    private let createDeviceCodeService: CreateDeviceCodeServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let opener: Opening
    private let uniqueIDGenerator: UniqueIDGenerating

    public init() {
        self.init(
            opener: Opener(),
            getAuthTokenService: GetAuthTokenService(),
            createDeviceCodeService: CreateDeviceCodeService(),
            uniqueIDGenerator: UniqueIDGenerator(),
            serverAuthenticationController: ServerAuthenticationController()
        )
    }

    init(
        opener: Opening,
        getAuthTokenService: GetAuthTokenServicing,
        createDeviceCodeService: CreateDeviceCodeServicing,
        uniqueIDGenerator: UniqueIDGenerating,
        serverAuthenticationController: ServerAuthenticationControlling
    ) {
        self.opener = opener
        self.getAuthTokenService = getAuthTokenService
        self.createDeviceCodeService = createDeviceCodeService
        self.uniqueIDGenerator = uniqueIDGenerator
        self.serverAuthenticationController = serverAuthenticationController
    }

    // MARK: - ServerSessionControlling

    public func authenticate(
        serverURL: URL,
        deviceCodeType: DeviceCodeType,
        onUserCode: @escaping (String) async -> Void,
        onOpeningBrowser: @escaping (URL) async -> Void,
        onAuthWaitBegin: () async -> Void
    ) async throws {
        // The `/auth/device` page is worded for the CLI, so the app stays on the link flow.
        let deviceAuthorization: ServerDeviceAuthorization? = switch deviceCodeType {
        case .cli: try await createDeviceCodeService.createDeviceCode(serverURL: serverURL)
        case .app: nil
        }

        let authURL: URL
        let deviceCode: String
        let pollInterval: Int
        let deadline: Date?
        if let deviceAuthorization {
            authURL = deviceAuthorization.verificationURL
            deviceCode = deviceAuthorization.deviceCode
            pollInterval = max(deviceAuthorization.interval, 1)
            deadline = Date().addingTimeInterval(TimeInterval(deviceAuthorization.expiresIn))
            await onUserCode(deviceAuthorization.userCode)
        } else {
            deviceCode = uniqueIDGenerator.uniqueID()
            authURL = linkFlowURL(serverURL: serverURL, deviceCode: deviceCode, deviceCodeType: deviceCodeType)
            pollInterval = 1
            deadline = nil
        }

        await onOpeningBrowser(authURL)

        try opener.open(url: authURL)

        await onAuthWaitBegin()

        #if canImport(TuistSupport)
            let tokens = try await ProgramStatusReporter.current.withBlockedStatus(
                kind: .auth,
                message: "Complete sign-in in your browser"
            ) {
                try await getAuthTokens(
                    serverURL: serverURL,
                    deviceCode: deviceCode,
                    pollInterval: pollInterval,
                    deadline: deadline
                )
            }
        #else
            let tokens = try await getAuthTokens(
                serverURL: serverURL,
                deviceCode: deviceCode,
                pollInterval: pollInterval,
                deadline: deadline
            )
        #endif
        let credentials = ServerCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
        try await ServerCredentialsStore.current.store(credentials: credentials, serverURL: serverURL)
    }

    public func whoami(serverURL: URL) async throws -> String? {
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: serverURL
        )
        else { return nil }
        switch token {
        case let .user(accessToken: accessToken, refreshToken: _):
            return accessToken.preferredUsername
        case .project, .account:
            return nil
        }
    }

    public func authenticatedHandle(serverURL: URL) async throws -> String {
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: serverURL
        )
        else {
            throw ServerSessionControllerError.unauthenticated
        }
        switch token {
        case let .user(accessToken: accessToken, refreshToken: _):
            guard let username = accessToken.preferredUsername else {
                throw ServerSessionControllerError.unauthenticated
            }
            return username
        case .project, .account:
            throw ServerSessionControllerError.unauthenticated
        }
    }

    public func logout(serverURL: URL) async throws {
        try await ServerCredentialsStore.current.delete(serverURL: serverURL)
        #if canImport(TuistSupport)
            AlertController.current.success(.alert("Successfully logged out."))
        #endif
    }

    private func linkFlowURL(serverURL: URL, deviceCode: String, deviceCodeType: DeviceCodeType) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth/device_codes/\(deviceCode)"
        components.queryItems = [
            URLQueryItem(
                name: "type",
                value: deviceCodeType.apiValue
            ),
        ]
        return components.url!
    }

    private func getAuthTokens(
        serverURL: URL,
        deviceCode: String,
        pollInterval: Int,
        deadline: Date?
    ) async throws -> ServerAuthenticationTokens {
        while true {
            if let tokens = try await getAuthTokenService.getAuthToken(
                serverURL: serverURL,
                deviceCode: deviceCode
            ) {
                return tokens
            }
            if let deadline, Date() >= deadline {
                throw ServerSessionControllerError.deviceCodeExpired
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)
        }
    }
}
