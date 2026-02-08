#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Mockable
    import Testing
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistLoader
    import TuistServer
    import TuistSupport
    import TuistTesting

    @testable import TuistBuildCommand

    struct BuildListCommandServiceTests {
        private let listBuildsService = MockListBuildsServicing()
        private let serverEnvironmentService = MockServerEnvironmentServicing()
        private let configLoader = MockConfigLoading()
        private let subject: BuildListCommandService!

        init() {
            subject = BuildListCommandService(
                listBuildsService: listBuildsService,
                serverEnvironmentService: serverEnvironmentService,
                configLoader: configLoader
            )
        }

        @Test(.withMockedEnvironment()) func run_when_full_handle_is_not_passed_and_absent_in_config() async throws {
            // Given
            let tuist = Tuist.test(fullHandle: nil)
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
            given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
            let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
            given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

            // When
            await #expect(throws: BuildListCommandServiceError.missingFullHandle, performing: {
                try await subject.run(
                    fullHandle: nil,
                    path: nil,
                    gitBranch: nil,
                    status: nil,
                    scheme: nil,
                    configuration: nil,
                    tags: [],
                    values: [],
                    page: nil,
                    pageSize: nil,
                    json: false
                )
            })
        }

        @Test(
            .withMockedEnvironment(arguments: ["--json"]),
            .withMockedNoora
        ) func run_when_full_handle_is_present_in_config_and_json() async throws {
            // Given
            let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
            let tuist = Tuist.test(fullHandle: fullHandle)
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
            given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
            let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
            given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
            let response = Operations.listBuilds.Output.Ok.Body.jsonPayload(
                builds: [
                    .init(
                        cacheable_task_local_hits_count: 3,
                        cacheable_task_remote_hits_count: 5,
                        cacheable_tasks_count: 10,
                        category: .clean,
                        configuration: "Debug",
                        duration: 5000,
                        git_branch: "main",
                        git_commit_sha: "abc123",
                        git_ref: "refs/heads/main",
                        id: UUID().uuidString,
                        inserted_at: Date(),
                        is_ci: false,
                        macos_version: "14.0",
                        model_identifier: "Mac14,2",
                        scheme: "MyApp",
                        status: .success,
                        url: "https://tuist.dev/builds/\(UUID().uuidString)",
                        xcode_version: "15.0"
                    ),
                ],
                pagination_metadata: .init(
                    current_page: 1,
                    has_next_page: false,
                    has_previous_page: false,
                    page_size: 10,
                    total_count: 1,
                    total_pages: 1
                )
            )

            given(listBuildsService).listBuilds(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                gitBranch: .value(nil),
                status: .value(nil),
                scheme: .value(nil),
                configuration: .value(nil),
                tags: .value([]),
                values: .value([]),
                page: .value(1),
                pageSize: .value(10)
            ).willReturn(response)

            // When
            try await subject.run(
                fullHandle: nil,
                path: nil,
                gitBranch: nil,
                status: nil,
                scheme: nil,
                configuration: nil,
                tags: [],
                values: [],
                page: nil,
                pageSize: nil,
                json: true
            )

            // Then
            let jsonEncoder = JSONEncoder()
            jsonEncoder.dateEncodingStrategy = .iso8601
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let buildJSON = String(data: try jsonEncoder.encode(response.builds), encoding: .utf8)!
            #expect(ui().contains(buildJSON))
        }

        @Test(
            .withMockedEnvironment(),
            .withMockedNoora
        ) func run_when_full_handle_is_present_in_config_and_no_json_and_empty_list() async throws {
            // Given
            let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
            let tuist = Tuist.test(fullHandle: fullHandle)
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
            given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
            let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
            given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
            let response = Operations.listBuilds.Output.Ok.Body.jsonPayload(
                builds: [],
                pagination_metadata: .init(
                    current_page: 1,
                    has_next_page: false,
                    has_previous_page: false,
                    page_size: 10,
                    total_count: 0,
                    total_pages: 0
                )
            )
            given(listBuildsService).listBuilds(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                gitBranch: .value(nil),
                status: .value(nil),
                scheme: .value(nil),
                configuration: .value(nil),
                tags: .value([]),
                values: .value([]),
                page: .value(1),
                pageSize: .value(10)
            ).willReturn(response)

            // When
            try await subject.run(
                fullHandle: nil,
                path: nil,
                gitBranch: nil,
                status: nil,
                scheme: nil,
                configuration: nil,
                tags: [],
                values: [],
                page: nil,
                pageSize: nil,
                json: false
            )

            // Then
            #expect(ui().contains("No builds found for project \(fullHandle)"))
        }

        @Test(
            .withMockedEnvironment(),
            .withMockedNoora
        ) func run_with_filters() async throws {
            // Given
            let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
            let tuist = Tuist.test(fullHandle: fullHandle)
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
            given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
            let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
            given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
            let response = Operations.listBuilds.Output.Ok.Body.jsonPayload(
                builds: [],
                pagination_metadata: .init(
                    current_page: 1,
                    has_next_page: false,
                    has_previous_page: false,
                    page_size: 10,
                    total_count: 0,
                    total_pages: 0
                )
            )
            given(listBuildsService).listBuilds(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                gitBranch: .value("main"),
                status: .value("success"),
                scheme: .value("MyApp"),
                configuration: .value("Debug"),
                tags: .value([]),
                values: .value([]),
                page: .value(1),
                pageSize: .value(10)
            ).willReturn(response)

            // When
            try await subject.run(
                fullHandle: nil,
                path: nil,
                gitBranch: "main",
                status: "success",
                scheme: "MyApp",
                configuration: "Debug",
                tags: [],
                values: [],
                page: nil,
                pageSize: nil,
                json: false
            )

            // Then
            #expect(
                ui()
                    .contains(
                        "No builds found for project \(fullHandle) with filters: branch: main, status: success, scheme: MyApp, configuration: Debug"
                    )
            )
        }

        @Test(
            .withMockedEnvironment(),
            .withMockedNoora
        ) func run_with_tags_and_values() async throws {
            // Given
            let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
            let tuist = Tuist.test(fullHandle: fullHandle)
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
            given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
            let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
            given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
            let response = Operations.listBuilds.Output.Ok.Body.jsonPayload(
                builds: [],
                pagination_metadata: .init(
                    current_page: 1,
                    has_next_page: false,
                    has_previous_page: false,
                    page_size: 10,
                    total_count: 0,
                    total_pages: 0
                )
            )
            given(listBuildsService).listBuilds(
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL),
                gitBranch: .value(nil),
                status: .value(nil),
                scheme: .value(nil),
                configuration: .value(nil),
                tags: .value(["ci", "nightly"]),
                values: .value(["ticket:PROJ-1234", "runner:macos-14"]),
                page: .value(1),
                pageSize: .value(10)
            ).willReturn(response)

            // When
            try await subject.run(
                fullHandle: nil,
                path: nil,
                gitBranch: nil,
                status: nil,
                scheme: nil,
                configuration: nil,
                tags: ["ci", "nightly"],
                values: ["ticket:PROJ-1234", "runner:macos-14"],
                page: nil,
                pageSize: nil,
                json: false
            )

            // Then
            #expect(
                ui()
                    .contains(
                        "No builds found for project \(fullHandle) with filters: tags: ci, nightly, values: ticket:PROJ-1234, runner:macos-14"
                    )
            )
        }
    }
#endif
