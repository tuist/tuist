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
                project: nil,
                path: nil,
                gitBranch: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(arguments: ["--json"]),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        let response = Operations.listBundles.Output.Ok.Body.jsonPayload(bundles: [
            .init(
                app_bundle_id: "app.tuist.dev",
                id: UUID().uuidString,
                inserted_at: Date(),
                install_size: 300,
                name: "Tuist",
                supported_platforms: [.ios],
                uploaded_by_account: "tuist",
                url: "https://tuist.dev/\(UUID().uuidString)",
                version: "1.2.3"
            ),
        ], meta: .init(has_next_page: false, has_previous_page: false, page_size: 1, total_count: 1))

        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
            path: nil,
            gitBranch: "main",
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleJSON = String(data: try jsonEncoder.encode(response), encoding: .utf8)!
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
        let response = Operations.listBundles.Output.Ok.Body.jsonPayload(
            bundles: [],
            meta: .init(has_next_page: false, has_previous_page: false, page_size: 1, total_count: 0)
        )
        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
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
    ) func run_when_full_handle_is_not_passed_and_present_in_config_and_no_json_and_non_empty_list() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        let bundle = Components.Schemas.Bundle(
            app_bundle_id: "app.tuist.dev",
            id: UUID().uuidString,
            inserted_at: Date(),
            install_size: 300,
            name: "Tuist",
            supported_platforms: [.ios],
            uploaded_by_account: "tuist",
            url: "https://tuist.dev/\(UUID().uuidString)",
            version: "1.2.3"
        )
        let response = Operations.listBundles.Output.Ok.Body.jsonPayload(bundles: [
            bundle,
        ], meta: .init(has_next_page: false, has_previous_page: false, page_size: 1, total_count: 1))
        given(listBundlesService).listBundles(
            fullHandle: .value(fullHandle),
            gitBranch: .value("main"),
            page: .value(nil),
            pageSize: .value(50),
            serverURL: .value(serverURL)
        ).willReturn(response)

        // When
        try await subject.run(
            project: nil,
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
        #expect(ui().contains(bundle.app_bundle_id.prefix(4)))
    }
}
