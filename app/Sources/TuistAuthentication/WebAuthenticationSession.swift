#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import AuthenticationServices
import Foundation
import TuistLogging

@MainActor
protocol WebAuthenticationSessionProtocol: AnyObject {
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? { get set }
    var prefersEphemeralWebBrowserSession: Bool { get set }
    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: WebAuthenticationSessionProtocol {}

@MainActor
final class WebAuthenticationSession {
    private let makeSession: (URL, String, @escaping ASWebAuthenticationSession.CompletionHandler)
        -> any WebAuthenticationSessionProtocol
    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    private var session: (any WebAuthenticationSessionProtocol)?
    private var continuation: CheckedContinuation<URL?, Error>?
    private var requestID: UUID?

    init(
        makeSession: @escaping (URL, String, @escaping ASWebAuthenticationSession.CompletionHandler)
            -> any WebAuthenticationSessionProtocol = {
                ASWebAuthenticationSession(url: $0, callback: .customScheme($1), completionHandler: $2)
            }
    ) {
        self.makeSession = makeSession
    }

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL? {
        guard continuation == nil else { throw AuthenticationError.authenticationInProgress }
        try Task.checkCancellation()
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.requestID = requestID
                self.continuation = continuation
                let session = makeSession(url, callbackURLScheme) { [weak self] url, error in
                    Task { @MainActor in
                        guard let subject = self else { return }
                        if let error {
                            let error = error as NSError
                            if error.domain == ASWebAuthenticationSessionErrorDomain,
                               error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                            {
                                subject.finish(.success(nil), requestID: requestID)
                            } else {
                                subject.finish(.failure(error), requestID: requestID)
                            }
                        } else if let url {
                            subject.finish(.success(url), requestID: requestID)
                        } else {
                            subject.finish(.failure(AuthenticationError.invalidCallbackURL), requestID: requestID)
                        }
                    }
                }
                session.presentationContextProvider = presentationContextProvider
                session.prefersEphemeralWebBrowserSession = true
                self.session = session
                let started = session.start()
                Logger.current.notice("System web authentication started=\(started)")
                if !started {
                    finish(.failure(AuthenticationError.unableToStartAuthentication), requestID: requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.requestID == requestID else { return }
                session?.cancel()
                finish(.failure(CancellationError()), requestID: requestID)
            }
        }
    }

    func cancel() {
        guard let requestID else { return }
        session?.cancel()
        finish(.success(nil), requestID: requestID)
    }

    private func finish(_ result: Result<URL?, Error>, requestID: UUID) {
        guard self.requestID == requestID, let continuation else { return }
        self.continuation = nil
        self.requestID = nil
        session = nil
        continuation.resume(with: result)
    }
}

private final class WebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
            let anchor = NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
            Logger.current.notice("Web authentication anchor visible=\(anchor.isVisible) key=\(anchor.isKeyWindow)")
            return anchor
        #else
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #endif
    }
}
