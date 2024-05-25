import MockableTest
import TuistAnalytics
import TuistApp
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistAnalyticsCloudBackendTests: TuistUnitTestCase {
    private var config: Cloud!
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var ciChecker: MockCIChecker!
    private var subject: TuistAnalyticsCloudBackend!

    override func setUp() {
        super.setUp()
        config = Cloud.test(
            url: URL(string: "https://cloud.tuist.io")!,
            projectId: "tuist-org/tuist"
        )
        createCommandEventService = .init()
        ciChecker = .init()
        subject = TuistAnalyticsCloudBackend(
            config: config,
            createCommandEventService: createCommandEventService,
            ciChecker: ciChecker
        )
    }

    override func tearDown() {
        config = nil
        createCommandEventService = nil
        ciChecker = nil
        subject = nil
        super.tearDown()
    }

    func test_send_when_is_not_ci() async throws {
        // Given
        ciChecker.isCIStub = false
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(config.projectId),
                serverURL: .value(config.url)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertPrinterOutputNotContains("You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
    }

    func test_send_when_is_ci() async throws {
        // Given
        ciChecker.isCIStub = true
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(config.projectId),
                serverURL: .value(config.url)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
    }
}
