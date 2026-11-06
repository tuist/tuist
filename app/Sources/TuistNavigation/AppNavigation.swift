import Foundation
import Observation

@Observable
public final class AppNavigation {
    public enum Tab: Hashable {
        case threads, previews, profile
    }

    public var tab = Tab.previews
    public var previewPath: [AppRoute] = []
    public private(set) var pendingURL: URL?
    public var webURL: URL?
    public var error: AppRouteError?

    public init() {}

    public func receive(_ url: URL) {
        // OAuth callbacks belong to the authentication session, not the navigation stack.
        guard (url.scheme?.lowercased() == "tuist" && url.host?.lowercased() == "app")
            || ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        else { return }
        pendingURL = url
    }

    public func openPendingURL(serverURL: URL) {
        guard let pendingURL else { return }
        self.pendingURL = nil
        do {
            navigate(to: try AppRoute(url: pendingURL, serverURL: serverURL))
        } catch {
            if AppRoute.isWebURL(pendingURL, serverURL: serverURL) {
                openWeb(pendingURL)
            } else {
                self.error = error as? AppRouteError ?? .invalidURL
            }
        }
    }

    public func openWeb(_ url: URL) {
        error = nil
        webURL = url
    }

    public func navigate(to route: AppRoute) {
        error = nil
        webURL = nil
        switch route {
        case .previews:
            tab = .previews
            previewPath = []
        case .profile:
            tab = .profile
        case .preview:
            tab = .previews
            previewPath = [route]
        }
    }

    public func reset() {
        tab = .previews
        previewPath = []
        webURL = nil
        error = nil
    }
}
