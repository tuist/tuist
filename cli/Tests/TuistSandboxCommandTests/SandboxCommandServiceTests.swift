import ArgumentParser
import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
@testable import TuistSandboxCommand

struct SandboxCommandServiceTests {
    private static let serverURL = URL(string: "https://sandbox-tests.tuist.dev")!
    private static let id = "a57a427c-1ffc-476f-9282-558ff3f61585"
    private static let pagination = """
    {"current_page":1,"page_size":20,"total_count":1,"total_pages":1,"has_next_page":false,"has_previous_page":false}
    """

    private let sandboxesService = MockSandboxesServicing()

    private func subject(fullHandle: String? = "resolved-account/project") async throws -> SandboxCommandService {
        let configLoader = MockConfigLoading()
        let directory = try await Environment.current.pathRelativeToWorkingDirectory("/project")
        given(configLoader).loadConfig(path: .value(directory)).willReturn(.test(fullHandle: fullHandle))
        let serverEnvironmentService = MockServerEnvironmentServicing()
        given(serverEnvironmentService).url(configServerURL: .value(Tuist.test().url)).willReturn(Self.serverURL)
        return SandboxCommandService(
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            sandboxesService: sandboxesService
        )
    }

    private static func sandbox(status: String?) -> String {
        let status = status.map { ",\"status\":\"\($0)\"" } ?? ""
        return """
        {"id":"\(id)","state":"running"\(status),"template":"default","vcpus":4,"memory_mb":8192,"workspace_gb":10,
         "inserted_at":"2026-11-01T10:00:00Z","updated_at":"2026-11-01T10:00:00Z"}
        """
    }

    private static func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    private static func values(account: String? = nil, json: Bool = false) -> SandboxOptions.Values {
        SandboxOptions.Values(account: account, path: "/project", json: json)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsTheProjectAccountsSandboxesWithTheirDashboardStatus() async throws {
        let page: SandboxesPage = try Self.decode(
            "{\"sandboxes\":[\(Self.sandbox(status: "active"))],\"pagination_metadata\":\(Self.pagination)}"
        )
        given(sandboxesService).listSandboxes(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            search: .value("orb"),
            status: .value("active"),
            vcpus: .value(4),
            sortBy: .value("last_active"),
            sortOrder: .value("asc"),
            page: .value(1),
            pageSize: .value(20)
        ).willReturn(page)

        try await subject().list(
            options: Self.values(),
            search: "orb",
            status: "active",
            vcpus: 4,
            sortBy: "last_active",
            sortOrder: "asc",
            page: 1,
            pageSize: 20
        )

        // The table truncates cells to the terminal width, so check the rendered row instead of the table text.
        #expect(ui().contains("Never"))
        #expect(Array(SandboxOutput.row(page.sandboxes[0]).prefix(5)) == [Self.id, "Active", "Linux", "4", "8 GB"])
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func anExplicitAccountNeedsNoFullHandleAndAnOlderServersStateStandsInForStatus() async throws {
        given(sandboxesService).getSandbox(
            accountHandle: .value("other-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id)
        ).willReturn(try Self.decode(Self.sandbox(status: nil)))

        try await subject(fullHandle: nil).show(options: Self.values(account: "other-account"), sandboxID: Self.id)

        #expect(ui().contains("Status: Running"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [false, true])
    func showsProgressWhileWaitingButKeepsJSONClean(json: Bool) async throws {
        given(sandboxesService).transitionSandbox(
            .value(.resume),
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id)
        ).willReturn(try Self.decode(Self.sandbox(status: "active")))

        try await subject().transition(.resume, options: Self.values(json: json), sandboxID: Self.id)

        if json {
            #expect(!ui().contains("Resum"))
            #expect(ui().contains("\"status\" : \"active\""))
        } else {
            #expect(ui().contains("Resumed sandbox \(Self.id)"))
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: ["paused", "running"])
    func pausingASandboxTheServerAlreadyPausedSucceeds(state: String) async throws {
        given(sandboxesService).transitionSandbox(
            .value(.pause),
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id)
        ).willThrow(SandboxesServiceError.refused("The sandbox is \(state)."))
        given(sandboxesService).getSandbox(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id)
        ).willReturn(try Self.decode(Self.sandbox(status: nil).replacingOccurrences(of: "running", with: state)))

        let pause = { try await subject().transition(.pause, options: Self.values(), sandboxID: Self.id) }

        if state == "paused" {
            try await pause()
            #expect(ui().contains("Sandbox \(Self.id) is paused"))
        } else {
            await #expect(throws: SandboxesServiceError.refused("The sandbox is running.")) { try await pause() }
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func createsAMacOSSandbox() async throws {
        let created = Self.sandbox(status: "starting")
            .replacingOccurrences(of: "\"vcpus\":4", with: "\"platform\":\"darwin\",\"vcpus\":8")
        given(sandboxesService).createSandbox(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            platform: .value(.darwin),
            template: .value(nil),
            vcpus: .value(8),
            memoryMB: .value(24576),
            workspaceGB: .value(nil)
        ).willReturn(try Self.decode(created))

        let command = try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "8", "--memory-mb", "24576"])
        try await subject().create(
            options: Self.values(),
            platform: command.platform.server,
            template: command.template,
            vcpus: command.vcpus,
            memoryMB: command.memoryMb,
            workspaceGB: command.workspaceGb
        )

        #expect(ui().contains("Platform: macOS"))
        #expect(ui().contains("vCPUs: 8"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func failsWithoutAnAccount() async throws {
        await #expect(throws: SandboxCommandError.missingAccount) {
            try await subject(fullHandle: nil).show(options: Self.values(), sandboxID: Self.id)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func execExitsWithTheCommandsExitStatus() async throws {
        given(sandboxesService).execSandboxCommand(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id),
            command: .value("make test"),
            timeoutMs: .value(30000)
        ).willReturn(try Self.decode("{\"exit_code\":2,\"stdout\":\"\",\"stderr\":\"\"}"))

        await #expect(throws: ExitCode(2)) {
            try await subject().exec(options: Self.values(), sandboxID: Self.id, command: "make test", timeoutMs: 30000)
        }
    }

    @Test
    func deleteRequiresConfirmationAndCreateRequiresAnOfferedShape() throws {
        #expect(throws: (any Error).self) { try SandboxDeleteCommand.parse([Self.id]) }
        #expect(throws: Never.self) { try SandboxDeleteCommand.parse([Self.id, "--yes"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "4", "--memory-mb", "4096"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "4"]) }
        #expect(throws: Never.self) { try SandboxCreateCommand.parse(["--vcpus", "4", "--memory-mb", "8192"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "8", "--memory-mb", "24576"]) }
        #expect(throws: Never.self) {
            try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "8", "--memory-mb", "24576"])
        }
        #expect(throws: (any Error).self) {
            try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "4", "--memory-mb", "8192"])
        }
        #expect(throws: (any Error).self) { try SandboxShowCommand.parse(["not-a-uuid"]) }
    }

    @Test
    func execJoinsTheCommandAfterTheSeparator() throws {
        let command = try SandboxExecCommand.parse([Self.id, "--timeout", "30", "--", "ls", "-la", "/workspace"])
        #expect(command.command == ["ls", "-la", "/workspace"])
        #expect(command.sandbox.sandboxID == Self.id)
    }
}
