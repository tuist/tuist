import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct BundleListCommandServiceTests {
    private let listBundlesService = MockListBundlesServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BundleListCommandService!

    init() {
        subject = BundleListCommandService(
            listBundlesService: listBundlesService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_not_pass_and_absent_in_config() async throws {
        // Given
        let tuist = Tuist.test(fullHandle: nil)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // When
        await #expect(throws: BundleListCommandServiceError.missingFullHandle, performing: {
            try await subject.run(
                fullHandle: nil,
                path: nil,
                gitBranch: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let serverBundle = ServerBundle.test(id: UUID().uuidString)
        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn([
            serverBundle,
        ])
        // When
        try await subject.run(
            fullHandle: nil,
            path: nil,
            gitBranch: "main",
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleJSON = String(data: try jsonEncoder.encode([serverBundle]), encoding: .utf8)!
        #expect(ui().contains(bundleJSON))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_no_json_and_empty_list() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn([
        ])
        // When
        try await subject.run(
            fullHandle: nil,
            path: nil,
            gitBranch: "main",
            json: false
        )

        // Then
        #expect(ui().contains("No bundles found for project \(fullHandle) for branch 'main'"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_no_json_and_non_empty_list() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let serverBundle = ServerBundle.test(id: UUID().uuidString)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn([
            serverBundle,
        ])
        // When
        try await subject.run(
            fullHandle: nil,
            path: nil,
            gitBranch: "main",
            json: false
        )

        // Then
        // Since this outputs a table, that auto-dimensions based on the width of the terminal emulator
        // and this logic is already tested in the Noora side, I'm just checking here that the bundle id
        // is included.
        //        ╭──────────────────────┬────────────┬────────┬─────────┬─────────────┬─────╮
        //        │ ID                   │ App bundl… │ Insta… │ Downlo… │ Inserted at │ URL │
        //        ├──────────────────────┼────────────┼────────┼─────────┼─────────────┼─────┤
        //        │ 9620034E-59B2-46BE-… │ com.examp… │ 1 MB   │ 512 KB  │ 3. Aug 202… │ (L… │
        //        ╰──────────────────────┴────────────┴────────┴─────────┴─────────────┴─────╯
        #expect(ui().contains(serverBundle.appBundleId.prefix(8)))
    }
}
