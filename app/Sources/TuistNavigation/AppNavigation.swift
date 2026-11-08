import Foundation
import Observation

@Observable
public final class AppNavigation {
    public enum Tab: Hashable {
        case jams, previews, profile
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

    public func openPendingURL(serverURL: URL, organization: String? = nil) {
        guard let pendingURL else { return }
        self.pendingURL = nil
        do {
            let route = try AppRoute(url: pendingURL, serverURL: serverURL)
            if let organization, case let .preview(account, _, _) = route, account != organization {
                throw AppRouteError.differentOrganization
            }
            navigate(to: route)
        } catch AppRouteError.differentOrganization {
            error = .differentOrganization
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

    public func reset(clearPending: Bool = false) {
        if clearPending { pendingURL = nil }
        tab = .previews
        previewPath = []
        webURL = nil
        error = nil
    }
}
