import Foundation
import Testing
import TuistNavigation

struct AppNavigationTests {
    private let production = URL(string: "https://tuist.dev")!

    @Test func canonical_urls_and_native_handoffs_match_the_shared_web_contract() throws {
        for fixture in try fixtures().previews {
            let server = try #require(URL(string: fixture.server))
            let canonical = try #require(URL(string: fixture.canonical))
            let handoff = try #require(URL(string: fixture.handoff))
            let route = AppRoute.preview(account: fixture.account, project: fixture.project, id: fixture.id)
            #expect(route.url(serverURL: server).absoluteString == fixture.canonical)
            #expect(route.handoffURL(serverURL: server).absoluteString == fixture.handoff)
            #expect(try AppRoute(url: canonical, serverURL: server) == route)
            #expect(try AppRoute(url: handoff, serverURL: server) == route)
        }
    }

    @Test func web_only_destinations_stay_in_the_browser_without_replacing_native_navigation() throws {
        let navigation = AppNavigation()
        navigation.navigate(to: .profile)
        for value in try fixtures().webOnly {
            let url = try #require(URL(string: value))
            #expect(throws: (any Error).self) { try AppRoute(url: url, serverURL: production) }
            navigation.receive(url)
            navigation.openPendingURL(serverURL: production)
            #expect(navigation.webURL == url)
            #expect(navigation.error == nil)
            #expect(navigation.tab == .profile)
            #expect(navigation.previewPath.isEmpty)
        }
        navigation.navigate(to: .previews)
        #expect(navigation.webURL == nil)
        let route = AppRoute.preview(account: "team", project: "mobile", id: "build-42")
        navigation.navigate(to: route)
        navigation.openWeb(route.url(serverURL: production))
        #expect(navigation.webURL == route.url(serverURL: production))
        #expect(navigation.previewPath == [route])
        navigation.reset()
        #expect(navigation.webURL == nil)
    }

    @Test func routes_round_trip_without_losing_identifiers() throws {
        let server = URL(string: "https://builds.example.com:8443/tuist/")!
        let routes: [AppRoute] = [.previews, .profile, .preview(account: "équipe", project: "ios+android", id: "build%?#42")]
        for route in routes {
            #expect(try AppRoute(url: route.url(serverURL: server), serverURL: server) == route)
        }
        #expect(AppRoute.profile.url(serverURL: server).absoluteString == "tuist://app/profile")
        #expect(AppRoute.previews.url(serverURL: server).absoluteString == "tuist://app/previews")
    }

    @Test func accepts_existing_preview_links_only_on_the_session_server() throws {
        let route = AppRoute.preview(account: "team", project: "mobile", id: "build-42")
        #expect(try AppRoute(
            url: URL(string: "https://TUIST.dev:443/team/mobile/previews/build-42")!,
            serverURL: production
        ) == route)
        let selfHosted = URL(string: "https://builds.example.com/tuist/")!
        #expect(try AppRoute(
            url: URL(string: "https://builds.example.com/tuist/team/mobile/previews/build-42")!,
            serverURL: selfHosted
        ) == route)
        #expect(throws: AppRouteError.differentServer) {
            try AppRoute(url: URL(string: "https://builds.example.com/team/mobile/previews/build-42")!, serverURL: selfHosted)
        }
    }

    @Test(arguments: [
        "tuist://app/team/mobile/previews/42?server=https%3A%2F%2Fstaging.tuist.dev",
        "tuist://app/team/mobile/previews/42?server=https%3A%2F%2Ftuist.dev%3A8443",
        "tuist://app/team/mobile/previews/42?server=http%3A%2F%2Ftuist.dev",
        "tuist://app/team/mobile/previews/42?server=https%3A%2F%2Ftuist.dev%2Fother",
        "https://evil.example/team/mobile/previews/42",
    ])
    func rejects_other_server_links(input: String) {
        #expect(throws: AppRouteError.differentServer) {
            try AppRoute(url: URL(string: input)!, serverURL: production)
        }
    }

    @Test(arguments: [
        "tuist://app/team/mobile/previews/42/extra", "tuist://app/team/mobile/previews/42/",
        "tuist://app//mobile/previews/42", "tuist://app/team/mobile/previews/",
        "tuist://app/team/mobile/previews/%2F", "tuist://app/team/mobile/previews/%5C",
        "tuist://app/team/mobile/previews/%00", "tuist://app/team/mobile/previews/%20",
        "tuist://app/team/../previews/42", "tuist://app/team/mobile/previews/%2E",
        "tuist://app/team/mobile/previews/42?",
        "tuist://app/team/mobile/previews/42?unknown=1", "tuist://app/profile?server=https://tuist.dev",
        "tuist://app/team/mobile/previews/42?server=https://tuist.dev&server=https://tuist.dev",
        "tuist://app/team/mobile/previews/42?server=", "tuist://user@app/profile",
        "tuist://app:123/profile", "tuist://app/profile#fragment", "tuist://oauth-callback?code=secret",
    ])
    func rejects_malformed_and_unrelated_links(input: String) {
        #expect(throws: (any Error).self) {
            try AppRoute(url: URL(string: input)!, serverURL: production)
        }
    }

    @Test func default_server_is_production_not_the_current_session() throws {
        let url = URL(string: "tuist://app/team/mobile/previews/42")!
        #expect(try AppRoute(url: url, serverURL: production) == .preview(account: "team", project: "mobile", id: "42"))
        #expect(throws: AppRouteError.differentServer) {
            try AppRoute(url: url, serverURL: URL(string: "https://staging.tuist.dev")!)
        }
    }

    @Test func pending_link_survives_authentication_and_is_consumed_once() {
        let navigation = AppNavigation()
        let detail = AppRoute.preview(account: "team", project: "mobile", id: "42")
        navigation.receive(AppRoute.profile.url(serverURL: production))
        navigation.receive(detail.url(serverURL: production))
        navigation.receive(URL(string: "tuist://oauth-callback?code=secret")!)
        navigation.reset()
        #expect(navigation.previewPath.isEmpty)
        #expect(navigation.pendingURL == detail.url(serverURL: production))
        navigation.openPendingURL(serverURL: production)
        #expect(navigation.tab == .previews)
        #expect(navigation.previewPath == [detail])
        #expect(navigation.pendingURL == nil)
        navigation.navigate(to: .profile)
        navigation.openPendingURL(serverURL: production)
        #expect(navigation.tab == .profile)
        navigation.receive(detail.url(serverURL: production))
        navigation.openPendingURL(serverURL: production)
        #expect(navigation.previewPath == [detail])
        navigation.navigate(to: .previews)
        #expect(navigation.previewPath.isEmpty)
    }

    @Test func wrong_server_does_not_replace_the_current_screen() {
        let navigation = AppNavigation()
        navigation.navigate(to: .profile)
        navigation.receive(URL(string: "tuist://app/team/mobile/previews/42")!)
        navigation.openPendingURL(serverURL: URL(string: "https://staging.tuist.dev")!)
        #expect(navigation.error == .differentServer)
        #expect(navigation.tab == .profile)
        #expect(navigation.previewPath.isEmpty)
        #expect(navigation.webURL == nil)
        #expect(navigation.pendingURL == nil)
    }

    @Test func organization_scope_applies_to_web_and_native_preview_links() {
        let route = AppRoute.preview(account: "team", project: "mobile", id: "42")
        for url in [route.url(serverURL: production), route.handoffURL(serverURL: production)] {
            let navigation = AppNavigation()
            navigation.navigate(to: .profile)
            navigation.receive(url)
            navigation.openPendingURL(serverURL: production, organization: "other-team")
            #expect(navigation.error == .differentOrganization)
            #expect(navigation.tab == .profile)
            #expect(navigation.previewPath.isEmpty)
            #expect(navigation.webURL == nil)
            #expect(navigation.pendingURL == nil)
            navigation.receive(url)
            navigation.openPendingURL(serverURL: production, organization: "team")
            #expect(navigation.previewPath == [route])
            #expect(navigation.error == nil)
        }
    }

    @Test func organization_switch_discards_pending_links_from_the_outgoing_session() {
        let navigation = AppNavigation()
        navigation.receive(AppRoute.preview(account: "team", project: "mobile", id: "42").url(serverURL: production))
        navigation.reset(clearPending: true)
        navigation.openPendingURL(serverURL: production, organization: "other-team")
        #expect(navigation.pendingURL == nil)
        #expect(navigation.previewPath.isEmpty)
        #expect(navigation.error == nil)
    }

    private func fixtures() throws -> Fixtures {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "routes", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Fixtures.self, from: Data(contentsOf: url))
    }

    private final class FixtureBundle: NSObject {}

    private struct Fixtures: Decodable {
        let previews: [Preview]
        let webOnly: [String]

        struct Preview: Decodable {
            let server: String
            let account: String
            let project: String
            let id: String
            let canonical: String
            let handoff: String
        }
    }
}
