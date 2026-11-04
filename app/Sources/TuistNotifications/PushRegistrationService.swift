import Foundation
import TuistAppStorage
import TuistLogging
import TuistServer

struct PushInstallation: Codable, Equatable {
    /// Lowercase UUID identifying this app installation on the server. Generated lazily on registration.
    var installationID: String?
    /// Whether the user turned on notifications on this device. Off until they opt in, and turned off again when
    /// they remove this device elsewhere.
    var isEnabled = false
}

/// Push installations keyed by server URL, since the app can sign in to self-hosted servers.
enum PushInstallationsKey: AppStorageKey {
    static let key = "pushInstallations"
    static let defaultValue: [String: PushInstallation] = [:]
}

/// Keeps this app installation registered for push notifications with the signed-in server.
struct PushRegistrationService: Sendable {
    private let registerPushDeviceService: RegisterPushDeviceServicing
    private let unregisterPushDeviceService: UnregisterPushDeviceServicing
    private let appStorage: AppStoring
    private let makeInstallationID: @Sendable () -> String

    init(
        registerPushDeviceService: RegisterPushDeviceServicing = RegisterPushDeviceService(),
        unregisterPushDeviceService: UnregisterPushDeviceServicing = UnregisterPushDeviceService(),
        appStorage: AppStoring = AppStorage(),
        makeInstallationID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.registerPushDeviceService = registerPushDeviceService
        self.unregisterPushDeviceService = unregisterPushDeviceService
        self.appStorage = appStorage
        self.makeInstallationID = makeInstallationID
    }

    func installationID(serverURL: URL) -> String? {
        installation(serverURL: serverURL).installationID
    }

    func isEnabled(serverURL: URL) -> Bool {
        installation(serverURL: serverURL).isEnabled
    }

    func register(
        token: String,
        environment: PushDeviceEnvironment,
        name: String?,
        serverURL: URL
    ) async throws {
        var installation = installation(serverURL: serverURL)
        guard installation.isEnabled else { return }

        for attempt in 1 ... 2 {
            let installationID = installation.installationID ?? makeInstallationID()
            if installation.installationID != installationID {
                installation.installationID = installationID
                try save(installation, serverURL: serverURL)
            }
            do {
                _ = try await registerPushDeviceService.registerPushDevice(
                    installationID: installationID,
                    token: token,
                    environment: environment,
                    name: name,
                    serverURL: serverURL
                )
                return
            } catch RegisterPushDeviceServiceError.removed {
                Logger.current.notice("This device was removed from the device list. Turning its notifications off.")
                try save(PushInstallation(installationID: nil, isEnabled: false), serverURL: serverURL)
                return
            } catch RegisterPushDeviceServiceError.unsupported {
                Logger.current.notice("The server doesn't support push notifications yet. Skipping registration.")
                return
            } catch let error as RegisterPushDeviceServiceError {
                switch error {
                case .conflict, .retired:
                    guard attempt == 1 else { throw error }
                    Logger.current.notice("Push installation can't be registered anymore. Rotating its ID.")
                    installation.installationID = nil
                default:
                    throw error
                }
            }
        }
    }

    /// Turning notifications off unregisters the installation, so turning them back on registers a new one.
    /// If unregistering fails, notifications stay on so the user can try again.
    func setEnabled(_ isEnabled: Bool, serverURL: URL) async throws {
        var installation = installation(serverURL: serverURL)
        if !isEnabled {
            try await unregister(serverURL: serverURL)
            installation.installationID = nil
        }
        installation.isEnabled = isEnabled
        try save(installation, serverURL: serverURL)
    }

    /// Unregisters the installation on a best-effort basis and forgets it. Call before clearing credentials.
    func signOut(serverURL: URL) async {
        do {
            try await unregister(serverURL: serverURL)
        } catch {
            Logger.current.error("Failed to unregister the push installation: \(error.localizedDescription)")
        }
        var installations = installations()
        installations[serverURL.absoluteString] = nil
        try? appStorage.set(PushInstallationsKey.self, value: installations)
    }

    /// Forgets every installation, so the next sign-in starts opted out, and returns whether any was opted in. The
    /// server retires registrations whose session ended, and deletes them with the account.
    @discardableResult
    func forgetAll() -> Bool {
        let wasEnabled = installations().values.contains(where: \.isEnabled)
        try? appStorage.set(PushInstallationsKey.self, value: [:])
        return wasEnabled
    }

    private func unregister(serverURL: URL) async throws {
        guard let installationID = installationID(serverURL: serverURL) else { return }
        try await unregisterPushDeviceService.unregisterPushDevice(
            installationID: installationID,
            serverURL: serverURL
        )
    }

    private func installations() -> [String: PushInstallation] {
        (try? appStorage.get(PushInstallationsKey.self)) ?? [:]
    }

    private func installation(serverURL: URL) -> PushInstallation {
        installations()[serverURL.absoluteString] ?? PushInstallation()
    }

    private func save(_ installation: PushInstallation, serverURL: URL) throws {
        var installations = installations()
        installations[serverURL.absoluteString] = installation
        try appStorage.set(PushInstallationsKey.self, value: installations)
    }
}
