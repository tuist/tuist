import AuthenticationServices
import Foundation
import Security
import SwiftUI
import TuistCodeCore

struct AppProfile: Decodable, Identifiable {
    let id: String
    let server: String
    let handle: String?
    let email: String?
    let organization: String?
    let organizations: [String]?
    let rejected: Bool
    /// Uses the Tuist app's session on this Mac.
    let shared: Bool?
}

struct AppSessionView: Decodable {
    var profiles: [AppProfile] = []
    var active_profile_id: String?
    var generation: UInt64 = 0

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
            case "http":
                result = try http(action)
            #if os(macOS)
                case "shared_list":
                    result = ["servers": try TuistAppSession.list()]
                case "shared_read":
                    guard let key = action["server"] as? String else { throw AppClientError(message: "Invalid server") }
                    result = ["value": try TuistAppSession.read(key) ?? NSNull()]
                case "shared_write":
                    guard let key = action["server"] as? String, let access = action["access_token"] as? String,
                          let refresh = action["refresh_token"] as? String
                    else { throw AppClientError(message: "Invalid session") }
                    try TuistAppSession.write(key, access: access, refresh: refresh)
                    result = ["ok": true]
            #endif
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

    private func http(_ action: [String: Any]) throws -> [String: Any] {
        guard let text = action["url"] as? String, let url = URL(string: text),
              url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""))
        else { throw AppClientError(message: String(localized: "A secure server URL is required.")) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = action["method"] as? String ?? "GET"
        request.allHTTPHeaderFields = action["headers"] as? [String: String]
        request.setValue("TuistCode/0.1", forHTTPHeaderField: "User-Agent")
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

@MainActor
final class AppClient: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var view = AppSessionView()
    @Published var error: String?
    @Published private(set) var signingIn = false
    private let host = NativeHost()
    private let queue = DispatchQueue(label: "dev.tuist.code.core", qos: .userInitiated)
    private var browser: ASWebAuthenticationSession?
    private var browserAttempt: UUID?

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
            if next.generation >= view.generation { view = next }
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
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tuist-code") { [weak self] url, error in
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
