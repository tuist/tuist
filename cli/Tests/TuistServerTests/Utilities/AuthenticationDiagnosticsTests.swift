import Foundation
import Testing

@testable import TuistServer

struct AuthenticationDiagnosticsTests {
    @Test func report_contains_environment_and_authentication_events_without_token_values() {
        let diagnostics = AuthenticationDiagnostics(maximumEventCount: 10)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        diagnostics.record(
            .tokenRefreshStarted(
                accessTokenExpiresAt: date.addingTimeInterval(60),
                refreshTokenExpiresAt: date.addingTimeInterval(120),
                coordinationStoreIdentifier: "coordination-store",
                credentialsStoreIdentifier: "credentials-store"
            ),
            at: date
        )
        diagnostics.record(
            .tokenRefreshFailed(errorType: "RefreshError"),
            at: date.addingTimeInterval(1)
        )

        let report = diagnostics.report(
            appVersion: "1.2.3",
            appBuild: "456",
            operatingSystemVersion: "iOS test version",
            generatedAt: date.addingTimeInterval(2)
        )

        #expect(report.contains("App version: 1.2.3 (456)"))
        #expect(report.contains("Operating system: iOS test version"))
        #expect(report.contains("token_refresh_started"))
        #expect(report.contains("coordination_store=coordination-store"))
        #expect(report.contains("credentials_store=credentials-store"))
        #expect(report.contains("token_refresh_failed error_type=RefreshError"))
        #expect(report.contains("never includes access or refresh token values"))
    }

    @Test func report_keeps_only_the_most_recent_events() {
        let diagnostics = AuthenticationDiagnostics(maximumEventCount: 2)

        diagnostics.record(.authenticationStateInitialized(state: "first"))
        diagnostics.record(.authenticationStateInitialized(state: "second"))
        diagnostics.record(.authenticationStateInitialized(state: "third"))

        let report = diagnostics.report(
            appVersion: "1",
            appBuild: "1",
            operatingSystemVersion: "test"
        )

        #expect(!report.contains("state=first"))
        #expect(report.contains("state=second"))
        #expect(report.contains("state=third"))
    }

    @Test func labels_are_stable_without_exposing_object_identifiers() {
        let diagnostics = AuthenticationDiagnostics()
        let firstStore = NSObject()
        let secondStore = NSObject()

        #expect(diagnostics.label(for: firstStore) == "store-1")
        #expect(diagnostics.label(for: firstStore) == "store-1")
        #expect(diagnostics.label(for: secondStore) == "store-2")
    }
}
