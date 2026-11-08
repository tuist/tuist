import AuthenticationServices
import CryptoKit
import Foundation
import OpenAPIRuntime
import SwiftUI
import TuistAppStorage
import TuistHTTP
import TuistLogging
import TuistServer

public enum AuthenticationError: LocalizedError {
    case invalidCallbackURL
    case missingAuthorizationCode
    case invalidTokenResponse
    case tokenExchangeFailed(statusCode: Int)
    case missingTokens
    case appleSignInFailed
    case missingAppleCredentials

    public var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return String(localized: "Invalid callback URL received")
        case .missingAuthorizationCode:
            return String(localized: "Authorization code not found")
        case .invalidTokenResponse:
            return String(localized: "Invalid response format")
        case let .tokenExchangeFailed(statusCode):
            return String(localized: "Token exchange failed with status code: \(statusCode)")
        case .missingTokens:
            return String(localized: "Access token or refresh token missing from response")
        case .appleSignInFailed:
            return String(localized: "Apple Sign In failed")
        case .missingAppleCredentials:
            return String(localized: "Missing Apple credentials from authorization")
        }
    }
}

public final class AuthenticationService: ObservableObject {
    @Published public var authenticationState: AuthenticationState
    @Published public private(set) var isSigningIn = false
    @Published public private(set) var selfHostedServerURL: String?
    @Published public private(set) var profiles: [StoredProfile] = []
    @Published public private(set) var activeProfileID: UUID?
    @Published public private(set) var isAddingProfile = false
    @Published public private(set) var isChangingProfile = false
    @Published public private(set) var isLoadingOrganizations = false
    @Published public private(set) var organizationsFailedToLoad = false

    var profileStore: ProfileStoring = KeychainProfileStore()
    public var beforeProfileChange: (() async -> (() async -> Void)?)?
    private let profilesEnabled: Bool
    private var previousServerSelection: AppServerConfiguration?
    private var organizationDiscovery: Task<Void, Never>?
    private var pendingRotations: [UUID: (previous: ServerCredentials, rotated: ServerCredentials)] = [:]
    private var rejectedOrganizationProfiles: Set<UUID> = []
    private let listOrganizationsService: ListOrganizationsServicing

    public var selectedOrganization: String? {
        profiles.first(where: { $0.id == activeProfileID }).map { $0.organization ?? $0.account.handle }
    }

    public var organizations: [StoredOrganization] {
        var result: [StoredOrganization] = []
        // A shared membership uses the current login when possible, without duplicate organization rows.
        let ordered = profiles.filter { $0.id == activeProfileID } + profiles.filter { $0.id != activeProfileID }
        for profile in ordered where profile.canSelectOrganization && !rejectedOrganizationProfiles.contains(profile.id) {
            let names = profile.organizations.flatMap { $0.isEmpty ? nil : $0 } ?? [profile.account.handle]
            for name in names {
                let organization = StoredOrganization(
                    profileID: profile.id, name: name, serverURL: profile.server?.url ?? ServerEnvironmentService().url()
                )
                if !result.contains(where: { $0.id == organization.id }) { result.append(organization) }
            }
        }
        return result.sorted { ($0.name, $0.serverURL.absoluteString) < ($1.name, $1.serverURL.absoluteString) }
    }

    private var signInEnvironment: ServerEnvironmentServicing {
        isAddingProfile
            ? AppServerEnvironmentService(appStorage: appStorage, useSignedInSession: false)
            : serverEnvironmentService
    }

    private let serverEnvironmentService: ServerEnvironmentServicing
    private let appStorage: AppStoring
    private var credentialsListenerTask: Task<Void, Never>?
    private let presentationContextProvider = ASWebAuthenticationPresentationContextProvider()
    private let redirectURI = "tuist://oauth-callback"
    private let deleteAccountService: DeleteAccountServicing
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        serverEnvironmentService: ServerEnvironmentServicing? = nil,
        appStorage: AppStoring = AppStorage(),
        deleteAccountService: DeleteAccountServicing = DeleteAccountService(),
        profilesEnabled: Bool = false,
        listOrganizationsService: ListOrganizationsServicing = ListOrganizationsService(),
        perform: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.tuistDefault.data(for: $0)
        }
    ) {
        self.serverEnvironmentService = serverEnvironmentService ?? AppServerEnvironmentService(appStorage: appStorage)
        self.appStorage = appStorage
        self.deleteAccountService = deleteAccountService
        self.profilesEnabled = profilesEnabled
        self.listOrganizationsService = listOrganizationsService
        self.perform = perform
        if profilesEnabled { ServerAuthenticationSession.current.advance() }

        authenticationState = (try? appStorage.get(AuthenticationStateKey.self)) ?? .loggedOut
        selfHostedServerURL = AppServerEnvironmentService(appStorage: appStorage).configuration?.url.absoluteString
        Logger.current.notice(
            "Authentication state initialized state=\(authenticationState.logDescription)"
        )

        startCredentialsListener()
    }

    deinit {
        credentialsListenerTask?.cancel()
    }

    private func startCredentialsListener() {
        credentialsListenerTask = Task {
            for await credentials in ServerCredentialsStore.current.credentialsChanged {
                let eventSession = ServerAuthenticationSession.current.id
                if profilesEnabled {
                    guard !isChangingProfile else { continue }
                    // Ignore queued events from a profile that is no longer active.
                    let current = try? await ServerCredentialsStore.current.read(serverURL: serverEnvironmentService.url())
                    guard current == credentials else { continue }
                }
                await MainActor.run {
                    guard !profilesEnabled || (!isChangingProfile && eventSession == ServerAuthenticationSession.current.id)
                    else { return }
                    do {
                        let expirationDates = tokenExpirationDates(credentials)
                        Logger.current.notice(
                            "Credentials changed has_credentials=\(credentials != nil) \(expirationDescription(expirationDates))"
                        )
                        try updateAuthenticationState(with: credentials)
                        if profilesEnabled, credentials != nil {
                            do { try saveActiveProfile(credentials: credentials) }
                            catch { Logger.current.error("Could not save the active profile: \(error.localizedDescription)") }
                        }
                    } catch {
                        Logger.current.error(
                            "Failed to update authentication state from credentials change: \(error.localizedDescription)"
                        )
                        authenticationState = .loggedOut
                        try? appStorage.set(AuthenticationStateKey.self, value: .loggedOut)
                    }
                }
            }
        }
    }

    private func updateAuthenticationState(with credentials: ServerCredentials?) throws {
        if let credentials {
            let account = try extractAccount(from: credentials.accessToken)
            // Signing in captures the selected server; refreshes keep the session's own server.
            let sessionServer = AppServerEnvironmentService(appStorage: appStorage).configuration
            authenticationState = .loggedIn(account: account, server: sessionServer)
            Logger.current.notice("Authentication state updated to logged in")
        } else {
            authenticationState = .loggedOut
            Logger.current.notice("Authentication state updated to logged out")
        }

        try? appStorage.set(AuthenticationStateKey.self, value: authenticationState)
    }

    private func extractAccount(from accessToken: String) throws -> Account {
        let jwt = try JWT.parse(accessToken)

        guard let email = jwt.email,
              let handle = jwt.preferredUsername
        else {
            throw AuthenticationError.missingTokens
        }

        return Account(email: email, handle: handle)
    }

    public func signOut() async {
        if profilesEnabled {
            await signOutProfile()
            return
        }
        Logger.current.notice(
            "Signing out and deleting credentials for server: \(serverEnvironmentService.url().absoluteString)"
        )
        do {
            try await ServerCredentialsStore.current.delete(serverURL: serverEnvironmentService.url())
        } catch {
            Logger.current.error(
                "Failed to delete credentials when signing out: \(error.localizedDescription)"
            )
        }

        await MainActor.run {
            try? updateAuthenticationState(with: nil)
        }
    }

    public func deleteAccount(_ account: Account) async throws {
        try await deleteAccountService.deleteAccount(
            handle: account.handle,
            serverURL: serverEnvironmentService.url()
        )
        await signOut()
    }

    /// Persists the server the app signs in to. Passing `nil` selects Tuist-hosted.
    @MainActor
    public func selectServer(_ serverURL: String?) async throws {
        try await whileSigningIn {
            let environment = AppServerEnvironmentService(appStorage: appStorage, useSignedInSession: !isAddingProfile)
            try await environment.selectServer(serverURL)
            selfHostedServerURL = environment.configuration?.url.absoluteString
        }
    }

    @MainActor
    public func signIn() async throws {
        try await whileSigningIn { try await startOAuth2Flow(with: "/oauth2/authorize") }
    }

    @MainActor
    public func signInWithGitHub() async throws {
        try await whileSigningIn { try await startOAuth2Flow(with: "/oauth2/github") }
    }

    @MainActor
    public func signInWithGoogle() async throws {
        try await whileSigningIn { try await startOAuth2Flow(with: "/oauth2/google") }
    }

    @MainActor
    public func signInWithApple(authorization: ASAuthorization) async throws {
        try await whileSigningIn {
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let identityTokenString = String(data: identityToken, encoding: .utf8),
                  let authorizationCode = appleIDCredential.authorizationCode,
                  let authorizationCodeString = String(data: authorizationCode, encoding: .utf8)
            else {
                throw AuthenticationError.missingAppleCredentials
            }

            try await exchangeAppleTokenForServerToken(
                identityToken: identityTokenString,
                authorizationCode: authorizationCodeString
            )
        }
    }

    @MainActor
    public func signInWithEmailAndPassword(email: String, password: String) async throws {
        try await whileSigningIn { try await exchangeEmailAndPassword(email: email, password: password) }
    }

    private func exchangeEmailAndPassword(email: String, password: String) async throws {
        let url = signInEnvironment.url().appending(path: "api/auth")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

        let parameters = [
            "email": email,
            "password": password,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        request.httpBody = jsonData

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            Logger.current.error(
                """
                Email and password sign in token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func exchangeAppleTokenForServerToken(
        identityToken: String,
        authorizationCode: String
    ) async throws {
        let url = signInEnvironment.url().appending(path: "api/auth/apple")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

        let parameters = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        request.httpBody = jsonData

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data)
        } else {
            Logger.current.error(
                """
                Apple sign in token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func startOAuth2Flow(with path: String) async throws {
        var urlComponents = URLComponents(
            url: signInEnvironment.url().appending(path: path),
            resolvingAgainstBaseURL: false
        )!

        let codeVerifier = codeVerifier()
        let state = UUID().uuidString
        urlComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: signInEnvironment.oauthClientId()),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge(from: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        try await authenticate(
            with: urlComponents.url!,
            codeVerifier: codeVerifier,
            state: state
        )
    }

    private func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func authenticate(
        with authURL: URL,
        codeVerifier: String,
        state: String
    ) async throws {
        let code: String? = try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "tuist"
            ) { callbackURL, error in
                if error != nil {
                    // The error often happens here when the user just cancels the authentication. Additionally, the errors coming
                    // from the callback are cryptic.
                    // The best thing here to do UX-wise is not to show any errors.
                    continuation.resume(returning: nil)
                    return
                }

                guard let callbackURL,
                      callbackURL.scheme == "tuist",
                      callbackURL.host == "oauth-callback",
                      URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "state" })?.value == state
                else {
                    continuation.resume(throwing: AuthenticationError.invalidCallbackURL)
                    return
                }

                guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: AuthenticationError.missingAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }
            authSession.presentationContextProvider = presentationContextProvider
            authSession.prefersEphemeralWebBrowserSession = true
            Task {
                await MainActor.run {
                    authSession.start()
                }
            }
        }
        if let code {
            try await exchangeCodeForToken(code, codeVerifier: codeVerifier)
        }
    }

    private func exchangeCodeForToken(
        _ code: String,
        codeVerifier: String
    ) async throws {
        let url = signInEnvironment.url().appending(path: "oauth2/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addRequestIDHeader()
        ClientFeatureFlags.addHeader(to: &request)

        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": signInEnvironment.oauthClientId(),
            "code_verifier": codeVerifier,
        ]

        let body = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidTokenResponse
        }

        if httpResponse.statusCode == 200 {
            try await handleTokenResponse(data, oauthClientID: signInEnvironment.oauthClientId())
        } else {
            Logger.current.error(
                """
                OAuth token exchange failed with status code: \(httpResponse.statusCode), \
                requestID: \(request.requestID ?? "unknown"), \
                responseRequestID: \(httpResponse.requestID ?? "unknown")
                """
            )
            throw AuthenticationError.tokenExchangeFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func handleTokenResponse(_ data: Data, oauthClientID: String? = nil) async throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthenticationError.invalidTokenResponse
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw AuthenticationError.missingTokens
        }

        if profilesEnabled {
            let account = try extractAccount(from: accessToken)
            let server = AppServerEnvironmentService(appStorage: appStorage, useSignedInSession: false).configuration
            let profile = StoredProfile(
                id: UUID(), account: account, server: server,
                credentials: ServerCredentials(accessToken: accessToken, refreshToken: refreshToken, oauthClientID: oauthClientID)
            )
            try await activateProfile(profile)
            return
        }

        try await ServerCredentialsStore.current.store(
            credentials: ServerCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                oauthClientID: oauthClientID
            ),
            serverURL: serverEnvironmentService.url()
        )
        let expirationDates = tokenExpirationDates(
            ServerCredentials(accessToken: accessToken, refreshToken: refreshToken)
        )
        Logger.current.notice(
            "Stored authentication credentials from token response \(expirationDescription(expirationDates))"
        )
    }

    private func tokenExpirationDates(_ credentials: ServerCredentials?) -> (
        accessToken: Date?,
        refreshToken: Date?
    ) {
        guard let credentials else { return (nil, nil) }
        return (
            accessToken: try? JWT.parse(credentials.accessToken).expiryDate,
            refreshToken: credentials.refreshToken.flatMap { try? JWT.parse($0).expiryDate }
        )
    }

    private func expirationDescription(_ expirationDates: (accessToken: Date?, refreshToken: Date?)) -> String {
        "access_token_expires_at=\(expirationDates.accessToken.map(format) ?? "unknown") "
            + "refresh_token_expires_at=\(expirationDates.refreshToken.map(format) ?? "unknown")"
    }

    private func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension AuthenticationState {
    fileprivate var logDescription: String {
        switch self {
        case .loggedIn:
            return "loggedIn"
        case .loggedOut:
            return "loggedOut"
        }
    }
}

private final class ASWebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthenticationService {
    /// Additive migration: the active legacy credential record remains authoritative and is never moved or removed.
    @MainActor
    public func loadProfiles() async throws {
        guard profilesEnabled else { return }
        try persistPendingRotations()
        var credentials = try await ServerCredentialsStore.current.read(serverURL: serverEnvironmentService.url())
        if case let .loggedIn(account, server) = authenticationState {
            if let credentials {
                let actualAccount = try extractAccount(from: credentials.accessToken)
                if actualAccount != account {
                    authenticationState = .loggedIn(account: actualAccount, server: server)
                    try appStorage.set(AuthenticationStateKey.self, value: authenticationState)
                }
            } else if let recovered = try profileStore.read().profiles
                .first(where: { $0.account == account && $0.server == server })
            {
                try await ServerCredentialsStore.current.store(
                    credentials: recovered.credentials, serverURL: serverEnvironmentService.url()
                )
                credentials = recovered.credentials
            }
        }
        try saveActiveProfile(credentials: credentials)
    }

    @MainActor
    private func persistPendingRotations() throws {
        for (id, rotation) in pendingRotations {
            var saved = try profileStore.read()
            guard let index = saved.profiles.firstIndex(where: { $0.id == id }),
                  saved.profiles[index].credentials == rotation.previous
            else {
                pendingRotations[id] = nil
                continue
            }
            let current = saved.profiles[index]
            saved.profiles[index] = StoredProfile(
                id: current.id, account: current.account, server: current.server, credentials: rotation.rotated,
                organization: current.organization, organizations: current.organizations,
                organizationsAccessDenied: current.organizationsAccessDenied
            )
            try profileStore.write(saved)
            pendingRotations[id] = nil
            profiles = saved.profiles
        }
    }

    @MainActor
    private func saveActiveProfile(credentials: ServerCredentials?) throws {
        var saved = try profileStore.read()
        if case let .loggedIn(account, server) = authenticationState, let credentials {
            let previous = saved.profiles.first { $0.id == saved.activeID && $0.account == account && $0.server == server }
                ?? saved.profiles.first { $0.account == account && $0.server == server }
            let profile = StoredProfile(
                id: previous?.id ?? UUID(), account: account, server: server, credentials: credentials,
                organization: previous?.organization, organizations: previous?.organizations,
                organizationsAccessDenied: previous?.organizationsAccessDenied
            )
            if let index = saved.profiles.firstIndex(where: { $0.id == profile.id }) {
                saved.profiles[index] = profile
            } else {
                saved.profiles.append(profile)
            }
            saved.activeID = profile.id
            try profileStore.write(saved)
        }
        profiles = saved.profiles
        activeProfileID = authenticationState == .loggedOut ? nil : saved.activeID
    }

    @MainActor
    public func beginAddingProfile() async throws {
        guard profilesEnabled, !isSigningIn, !isChangingProfile else { return }
        try await loadProfiles()
        previousServerSelection = try appStorage.get(AppServerConfigurationKey.self)
        isAddingProfile = true
    }

    @MainActor
    public func cancelAddingProfile() {
        guard isAddingProfile, !isSigningIn, !isChangingProfile else { return }
        try? appStorage.set(AppServerConfigurationKey.self, value: previousServerSelection)
        selfHostedServerURL = previousServerSelection?.url.absoluteString
        isAddingProfile = false
    }

    @MainActor
    public func refreshOrganizations() async {
        guard profilesEnabled, !isChangingProfile, !isSigningIn else { return }
        if let organizationDiscovery { await organizationDiscovery.value; return }
        isLoadingOrganizations = true
        organizationsFailedToLoad = false
        let task = Task { @MainActor in
            defer { isLoadingOrganizations = false }
            do { try await loadProfiles() }
            catch { organizationsFailedToLoad = true; return }
            for profile in profiles {
                do {
                    let url = profile.server?.url ?? ServerEnvironmentService().url()
                    let names: [String]
                    if profile.id == activeProfileID {
                        names = try await listOrganizationsService.listOrganizations(serverURL: url)
                        try await loadProfiles()
                    } else {
                        var expected = profile.credentials
                        let store = ProfileCredentialsStore(credentials: expected, serverURL: url) { credentials in
                            self.pendingRotations[profile.id] = (expected, credentials)
                            try self.persistPendingRotations()
                            expected = credentials
                        }
                        names = try await ServerCredentialsStore.$current.withValue(store) {
                            try await ServerAuthenticationSession.$current.withValue(ServerAuthenticationSession()) {
                                try await CachedValueStore.$current.withValue(CachedValueStore()) {
                                    try await self.listOrganizationsService.listOrganizations(serverURL: url)
                                }
                            }
                        }
                    }
                    var saved = try profileStore.read()
                    guard let index = saved.profiles.firstIndex(where: { $0.id == profile.id }) else { continue }
                    saved.profiles[index].organizations = Array(Set(names)).sorted()
                    saved.profiles[index].organizationsAccessDenied = nil
                    try profileStore.write(saved)
                    rejectedOrganizationProfiles.remove(profile.id)
                    profiles = saved.profiles
                } catch {
                    organizationsFailedToLoad = true
                    if isOrganizationAccessDenied(error) {
                        rejectedOrganizationProfiles.insert(profile.id)
                        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                            profiles[index].organizationsAccessDenied = true
                        }
                        do {
                            var saved = try profileStore.read()
                            if let index = saved.profiles.firstIndex(where: { $0.id == profile.id }) {
                                saved.profiles[index].organizationsAccessDenied = true
                                try profileStore.write(saved)
                            }
                        } catch {
                            Logger.current.error("Could not persist saved login rejection: \(error.localizedDescription)")
                        }
                    }
                    Logger.current.error("Could not load saved login organizations: \(error.localizedDescription)")
                }
            }
        }
        organizationDiscovery = task
        await task.value
        organizationDiscovery = nil
        // An existing login remains usable when offline or when it has no organization memberships.
        if let active = profiles.first(where: { $0.id == activeProfileID }),
           !organizations.contains(where: { $0.profileID == active.id && $0.name == selectedOrganization }),
           let first = organizations.first(where: { $0.profileID == active.id })
        {
            do { try await switchOrganization(first) }
            catch { organizationsFailedToLoad = true }
        }
    }

    @MainActor
    public func switchOrganization(_ organization: StoredOrganization) async throws {
        guard profilesEnabled, !isSigningIn, !isChangingProfile else { return }
        await organizationDiscovery?.value
        guard organizations.contains(organization),
              var profile = profiles.first(where: { $0.id == organization.profileID })
        else { throw ProfileStorageError() }
        guard profile.id != activeProfileID || organization.name != selectedOrganization else { return }
        profile.organization = organization.name
        try await activateProfile(profile)
    }

    @MainActor
    public func switchProfile(_ id: UUID) async throws {
        guard profilesEnabled, !isSigningIn, !isChangingProfile, id != activeProfileID else { return }
        try await loadProfiles()
        guard let profile = profiles.first(where: { $0.id == id }), profile.canSelectOrganization,
              !rejectedOrganizationProfiles.contains(id)
        else {
            throw ProfileStorageError()
        }
        try await activateProfile(profile)
    }

    private func isOrganizationAccessDenied(_ error: any Error) -> Bool {
        switch error {
        case ListOrganizationsServiceError.unauthorized, ListOrganizationsServiceError.forbidden,
             RefreshAuthTokenServiceError.unauthorized:
            return true
        case let error as ClientError:
            return isOrganizationAccessDenied(error.underlyingError)
        case let error as CredentialAcquisitionError:
            return isOrganizationAccessDenied(error.underlyingError)
        default:
            return false
        }
    }

    @MainActor
    private func activateProfile(_ profile: StoredProfile) async throws {
        guard !isChangingProfile else { return }
        isChangingProfile = true
        defer { isChangingProfile = false }
        await organizationDiscovery?.value
        try await loadProfiles()
        let restoreNotifications = await beforeProfileChange?()
        do {
            await ServerAuthenticationSession.current.advanceAfterRefreshing()
            // Push cleanup may refresh the outgoing credentials; archive that final rotation before switching.
            try await loadProfiles()
            let previous = try profileStore.read()
            let previousState = authenticationState
            let previousURL = serverEnvironmentService.url()
            let previousCredentials = try await ServerCredentialsStore.current.read(serverURL: previousURL)
            var saved = previous
            let latest = previous.profiles.first { $0.id == profile.id }
            let profile = StoredProfile(
                id: profile.id, account: profile.account, server: profile.server,
                credentials: latest?.credentials ?? profile.credentials,
                organization: profile.organization, organizations: latest?.organizations ?? profile.organizations,
                organizationsAccessDenied: latest?.organizationsAccessDenied ?? profile.organizationsAccessDenied
            )
            saved.profiles.removeAll { $0.id == profile.id }
            saved.profiles.append(profile)
            saved.activeID = profile.id
            try profileStore.write(saved)
            let nextState = AuthenticationState.loggedIn(account: profile.account, server: profile.server)
            do {
                try appStorage.set(AuthenticationStateKey.self, value: nextState)
                let url = profile.server?.url ?? ServerEnvironmentService().url()
                try await ServerCredentialsStore.current.store(credentials: profile.credentials, serverURL: url)
                authenticationState = nextState
                profiles = saved.profiles
                activeProfileID = profile.id
                isAddingProfile = false
            } catch {
                try? appStorage.set(AuthenticationStateKey.self, value: previousState)
                if let previousCredentials {
                    try? await ServerCredentialsStore.current.store(credentials: previousCredentials, serverURL: previousURL)
                }
                try? profileStore.write(previous)
                throw error
            }
        } catch {
            await restoreNotifications?()
            throw error
        }
    }

    @MainActor
    private func signOutProfile() async {
        guard !isChangingProfile, !isSigningIn else { return }
        isChangingProfile = true
        defer { isChangingProfile = false }
        await organizationDiscovery?.value
        var restoreNotifications: (() async -> Void)?
        do {
            try await loadProfiles()
            restoreNotifications = await beforeProfileChange?()
            await ServerAuthenticationSession.current.advanceAfterRefreshing()
            try await loadProfiles()
            let previous = try profileStore.read()
            let previousState = authenticationState
            let url = serverEnvironmentService.url()
            let credentials = try await ServerCredentialsStore.current.read(serverURL: url)
            var saved = previous
            saved.profiles.removeAll { $0.id == activeProfileID }
            saved.activeID = nil
            do {
                try profileStore.write(saved)
                try await ServerCredentialsStore.current.delete(serverURL: url)
                try appStorage.set(AuthenticationStateKey.self, value: .loggedOut)
            } catch {
                try? profileStore.write(previous)
                try? appStorage.set(AuthenticationStateKey.self, value: previousState)
                if let credentials {
                    try? await ServerCredentialsStore.current.store(credentials: credentials, serverURL: url)
                }
                throw error
            }
            authenticationState = .loggedOut
            profiles = saved.profiles
            activeProfileID = nil
            restoreNotifications = nil
            isChangingProfile = false
            if let next = saved.profiles.first { try await activateProfile(next) }
        } catch {
            await restoreNotifications?()
            isChangingProfile = false
            Logger.current.error("Could not sign out of the profile: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func whileSigningIn(_ action: () async throws -> Void) async throws {
        guard !isSigningIn, !isChangingProfile, authenticationState == .loggedOut || isAddingProfile else { return }
        do {
            isSigningIn = true
            defer { isSigningIn = false }
            try await action()
        }
        if profilesEnabled, !isAddingProfile, case .loggedIn = authenticationState {
            await refreshOrganizations()
        }
    }
}
