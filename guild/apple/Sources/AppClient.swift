import AuthenticationServices
import Foundation
import OSLog
import Security
import SwiftUI
import TuistGuildCore

private let coreLog = Logger(subsystem: "dev.tuist.guild", category: "core")

struct AppProfile: Decodable, Identifiable {
    let id: String
    let server: String
    let handle: String?
    let email: String?
    let rejected: Bool
}

struct AppNavigation: Decodable {
    enum Tab: String, Decodable, Hashable {
        case threads, profile
    }

    var tab: Tab = .threads
    var thread_id: String?
    var path: String = "/threads"
    var revision: UInt64 = 0
}

/// A personal account or organization from any saved profile; selecting it
/// switches to the profile that owns it.
struct AppAccount: Decodable, Identifiable {
    let profile_id: String
    let name: String
    let server: String
    let handle: String
    let personal: Bool
    let rejected: Bool
    let selected: Bool

    var id: String { "\(profile_id)/\(name)" }
}

struct AppSessionView: Decodable {
    var profiles: [AppProfile] = []
    var accounts: [AppAccount] = []
    var active_profile_id: String?
    var generation: UInt64 = 0
    var navigation = AppNavigation()

    var active: AppProfile? { profiles.first { $0.id == active_profile_id } }
}

struct AppClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class NativeHost: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var response: UnsafeMutablePointer<CChar>?
    private let keychain: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.tuist.code.profiles",
        kSecAttrAccount as String: "profiles-v1",
        kSecAttrSynchronizable as String: false,
    ]
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    deinit { free(response) }

    func urlSession(
        _: URLSession, task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func perform(_ input: String) -> UnsafeMutablePointer<CChar>? {
        let result: [String: Any]
        do {
            let action = try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any] ?? [:]
            switch action["type"] as? String {
            case "read":
                var query = keychain
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var value: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &value)
                if status == errSecItemNotFound {
                    result = ["value": NSNull()]
                } else if status == errSecSuccess, let data = value as? Data,
                          let text = String(data: data, encoding: .utf8)
                {
                    result = ["value": text]
                } else {
                    throw AppClientError(message: String(localized: "Your saved profiles could not be read."))
                }
            case "write":
                guard let text = action["value"] as? String else { throw AppClientError(message: "Invalid vault") }
                let value = [kSecValueData as String: Data(text.utf8)]
                var status = SecItemUpdate(keychain as CFDictionary, value as CFDictionary)
                if status == errSecItemNotFound {
                    var item = keychain.merging(value) { _, new in new }
                    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    status = SecItemAdd(item as CFDictionary, nil)
                }
                guard status == errSecSuccess else {
                    throw AppClientError(
                        message: String(localized: "Your saved profiles could not be updated. Please try again.")
                    )
                }
                result = ["ok": true]
            case "log":
                // The core's own messages: boot steps and migrations, never tokens.
                let message = action["message"] as? String ?? ""
                coreLog.info("\(message, privacy: .public)")
                result = ["ok": true]
            case "store_directory":
                result = ["path": try storeDirectory().path]
            case "http":
                do {
                    result = try http(action)
                } catch let error as URLError where Self.offline.contains(error.code) {
                    // Only connectivity counts as offline; the core then answers
                    // from its store. TLS and other failures stay errors.
                    result = ["error": "offline"]
                }
            default:
                throw AppClientError(message: "Invalid host operation")
            }
        } catch {
            result = ["error": error.localizedDescription]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{\"error\":\"Native operation failed\"}".utf8)
        free(response)
        response = strdup(String(decoding: data, as: UTF8.self))
        return response
    }

    /// Where the core keeps its SQLite stores, one per profile: Application
    /// Support, out of backups because the server holds the authoritative copy.
    /// Files get the default protection class, so background wakes after the
    /// first unlock can open them.
    private func storeDirectory() throws -> URL {
        var directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("dev.tuist.guild/store", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        return directory
    }

    private static let offline: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    private func http(_ action: [String: Any]) throws -> [String: Any] {
        guard let text = action["url"] as? String, let url = URL(string: text),
              url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""))
        else { throw AppClientError(message: String(localized: "A secure server URL is required.")) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = action["method"] as? String ?? "GET"
        request.allHTTPHeaderFields = action["headers"] as? [String: String]
        request.setValue("TuistGuild/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = (action["body"] as? String).map { Data($0.utf8) }
        let completed = DispatchSemaphore(value: 0)
        let box = HTTPResult()
        let task = session.dataTask(with: request) { data, response, error in
            box.result = if let error {
                .failure(error)
            } else if (data?.count ?? 0) > 8 * 1024 * 1024 {
                .failure(URLError(.dataLengthExceedsMaximum))
            } else if let response = response as? HTTPURLResponse {
                .success(["status": response.statusCode, "body": String(decoding: data ?? Data(), as: UTF8.self)])
            } else {
                .failure(AppClientError(message: String(localized: "The server returned an invalid response.")))
            }
            completed.signal()
        }
        task.resume()
        guard completed.wait(timeout: .now() + 35) == .success else {
            task.cancel()
            throw URLError(.timedOut)
        }
        return try box.result!.get()
    }

    private final class HTTPResult: @unchecked Sendable {
        var result: Result<[String: Any], Error>?
    }
}

@MainActor @Observable
final class AppClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var view = AppSessionView()
    var error: String?
    private(set) var signingIn = false
    @ObservationIgnored private let host = NativeHost()
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.tuist.code.core", qos: .userInitiated)
    @ObservationIgnored private var browser: ASWebAuthenticationSession?
    @ObservationIgnored private var browserAttempt: UUID?
    @ObservationIgnored private var started = false

    /// Launch arguments are consumed once, after the core boots.
    func start() async {
        guard !started else { return }
        started = true
        // Loads profiles and migrates local stores before any screen reads them.
        await perform("boot")
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--navigate"), index + 1 < arguments.count {
            await perform("navigate", ["url": arguments[index + 1]])
        }
    }

    func openURL(_ url: URL) async {
        // ASWebAuthenticationSession owns OAuth completion and state validation.
        // All other URLs go to the core, including validation of server origins.
        guard !(url.scheme?.lowercased() == "tuist-guild" && url.host?.lowercased() == "oauth-callback") else { return }
        await perform("navigate", ["url": url.absoluteString])
    }

    func call(_ operation: String, _ args: [String: Any] = [:]) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: ["operation": operation, "args": args])
        let host = host
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let text = String(decoding: request, as: UTF8.self)
                let pointer = text.withCString { request in
                    tuist_app_call(request, { action, context in
                        guard let action, let context else { return nil }
                        return Unmanaged<NativeHost>.fromOpaque(context).takeUnretainedValue().perform(String(cString: action))
                    }, Unmanaged.passUnretained(host).toOpaque())
                }
                guard let pointer else {
                    continuation.resume(throwing: AppClientError(message: "The Rust client could not respond."))
                    return
                }
                let data = Data(String(cString: pointer).utf8)
                tuist_app_free(pointer)
                continuation.resume(returning: data)
            }
        }
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let value = response["view"], !(value is NSNull) {
            let next = try JSONDecoder().decode(AppSessionView.self, from: JSONSerialization.data(withJSONObject: value))
            if next.generation > view.generation ||
                (next.generation == view.generation && next.navigation.revision >= view.navigation.revision)
            { view = next }
        }
        if let error = response["error"] as? String { throw AppClientError(message: error) }
        return response["data"] as? [String: Any] ?? [:]
    }

    func perform(_ operation: String, _ args: [String: Any] = [:]) async {
        do { _ = try await call(operation, args) }
        catch { self.error = error.localizedDescription }
    }

    func signIn(server: String, provider: String) async {
        guard !signingIn else { return }
        signingIn = true
        let attempt = UUID()
        browserAttempt = attempt
        do {
            let data = try await call("begin_sign_in", ["server": server, "provider": provider])
            guard browserAttempt == attempt, let text = data["url"] as? String, let url = URL(string: text) else {
                throw AppClientError(message: String(localized: "Sign-in could not be started."))
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tuist-guild") { [weak self] url, error in
                Task { @MainActor in
                    guard let self, self.browserAttempt == attempt else { return }
                    self.browserAttempt = nil
                    self.browser = nil
                    self.signingIn = false
                    if let url {
                        await self.perform("finish_sign_in", ["url": url.absoluteString])
                    } else {
                        await self.perform("cancel_sign_in")
                        if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            guard session.start() else { throw AppClientError(message: String(localized: "Sign-in could not be started.")) }
        } catch {
            browserAttempt = nil
            browser = nil
            signingIn = false
            self.error = error.localizedDescription
            await perform("cancel_sign_in")
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
            NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }

    func cancelSignIn() async {
        guard signingIn else { return }
        browserAttempt = nil
        browser?.cancel()
        browser = nil
        await perform("cancel_sign_in")
        signingIn = false
    }
}
