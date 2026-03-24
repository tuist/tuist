import Testing
@testable import TuistSupport
@testable import TuistTesting

struct XcodeControllerIntegrationTests {
    let subject: XcodeController
    init() {
        subject = XcodeController()
    }

    @Test
    func selected_version_succeeds() async throws {
        // When
        let got = try await subject.selectedVersion()

        // Then
        got
    }
}
