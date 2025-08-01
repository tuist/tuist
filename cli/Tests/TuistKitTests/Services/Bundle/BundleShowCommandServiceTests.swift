import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct BundleShowCommandServiceTests {
    private let getBundleService = MockGetBundleServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BundleShowCommandService!
    
    init() {
        subject = BundleShowCommandService()
    }

    @Test func run_when_full_handle_is_missing() async throws {
//        // Given
//        let bundle = ServerBundle.test()
//
//        // When
//        try await subject.run(
//            fullHandle: "",
//            bundleId: "bundle-123",
//            path: nil,
//            json: false
//        )
    }
}
