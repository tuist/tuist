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

struct SandboxCommandServiceTests { // swiftlint:disable:this type_body_length
    private static let serverURL = URL(string: "https://sandbox-tests.tuist.dev")!
    private static let id = "a57a427c-1ffc-476f-9282-558ff3f61585"
    private static let pagination = """
    {"current_page":1,"page_size":20,"total_count":1,"total_pages":1,"has_next_page":false,"has_previous_page":false}
    """

    private let sandboxesService = MockSandboxesServicing()

    private func subject(
        fullHandle: String? = "resolved-account/project",
        clock: FakeClock? = nil
    ) async throws -> SandboxCommandService {
        let configLoader = MockConfigLoading()
        let directory = try await Environment.current.pathRelativeToWorkingDirectory("/project")
        given(configLoader).loadConfig(path: .value(directory)).willReturn(.test(fullHandle: fullHandle))
        let serverEnvironmentService = MockServerEnvironmentServicing()
        given(serverEnvironmentService).url(configServerURL: .value(Tuist.test().url)).willReturn(Self.serverURL)
        guard let clock else {
            return SandboxCommandService(
                configLoader: configLoader,
                serverEnvironmentService: serverEnvironmentService,
                sandboxesService: sandboxesService
            )
        }
        return SandboxCommandService(
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            sandboxesService: sandboxesService,
            now: { clock.now },
            sleep: { clock.advance($0) },
            onWait: { clock.notice($0) }
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
    func createsALinuxSandboxWithAGuarantee() async throws {
        let created = Self.sandbox(status: "starting")
            .replacingOccurrences(
                of: "\"vcpus\":4",
                with: "\"vcpus\":16,\"guaranteed_vcpus\":2,\"lifetime_seconds\":1800,\"expires_at\":\"2026-11-01T10:30:00Z\""
            )
        given(sandboxesService).createSandbox(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            platform: .value(.linux),
            template: .value(nil),
            xcodeVersion: .value(nil),
            vcpus: .value(nil),
            memoryMB: .value(nil),
            workspaceGB: .value(nil),
            guaranteedVCPUs: .value(2),
            lifetimeSeconds: .value(1800)
        ).willReturn(try Self.decode(created))

        let command = try SandboxCreateCommand.parse(["--guaranteed-vcpus", "2", "--lifetime-minutes", "30"])
        try await subject().create(
            options: Self.values(),
            platform: command.resolvedPlatform.server,
            template: command.template,
            xcodeVersion: command.xcode,
            vcpus: command.vcpus,
            memoryGB: command.memoryGB,
            workspaceGB: command.workspaceGb,
            guaranteedVCPUs: command.guaranteedVCPUs,
            lifetimeMinutes: command.lifetimeMinutes
        )

        #expect(ui().contains("Guaranteed: 2 vCPUs"))
        #expect(ui().contains("Lifetime: 30m, expires"))
        // The server takes 5 minutes to a day.
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--lifetime-minutes", "4"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--lifetime-minutes", "1441"]) }
        // A macOS sandbox holds every vCPU, and only the offered guarantees go.
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--platform", "macos", "--guaranteed-vcpus", "2"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--guaranteed-vcpus", "3"]) }
    }

    private static let fleetBusy = SandboxesServiceError.unavailable(
        SandboxServerError(message: "Every sandbox host is busy right now.", code: "fleet_busy")
    )

    /// Every create takes 25 seconds on the clock, as the server's wait for a host does, and answers `answers` in
    /// turn (the last one repeats). Past 100 attempts it fails differently, so a loop that ignores its deadline
    /// fails the test instead of hanging it.
    private func givenCreates(_ answers: [Result<String, SandboxesServiceError>], clock: FakeClock) {
        given(sandboxesService).createSandbox(
            accountHandle: .any, serverURL: .any, platform: .any, template: .any, xcodeVersion: .any, vcpus: .any,
            memoryMB: .any, workspaceGB: .any, guaranteedVCPUs: .any, lifetimeSeconds: .any
        ).willProduce { _, _, _, _, _, _, _, _, _, _ in
            let attempt = clock.attempt()
            guard attempt < 100 else { throw SandboxesServiceError.unknownError(599) }
            clock.advance(25)
            switch answers[min(attempt, answers.count - 1)] {
            case let .success(json): return try Self.decode(json)
            case let .failure(error): throw error
            }
        }
    }

    private func create(clock: FakeClock, waitTimeout: String?) async throws {
        let command = try SandboxCreateCommand.parse(
            ["--platform", "macos"] + (waitTimeout.map { ["--wait-timeout", $0] } ?? [])
        )
        try await subject(clock: clock).create(
            options: Self.values(),
            platform: command.resolvedPlatform.server,
            template: nil,
            vcpus: nil,
            memoryGB: nil,
            workspaceGB: nil,
            waitTimeout: try command.waitTimeoutSeconds
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func waitTimeoutRetriesFleetBusyUntilAHostFreesUp() async throws {
        let clock = FakeClock()
        givenCreates(
            [
                .failure(Self.fleetBusy),
                .failure(Self.fleetBusy),
                .failure(Self.fleetBusy),
                .success(Self.sandbox(status: "active")),
            ],
            clock: clock
        )

        try await create(clock: clock, waitTimeout: "5m")

        #expect(clock.attemptTimes == [0, 30, 60, 90])
        #expect(ui().contains("Sandbox booted"))
        // The server's reason, once at the start and then about once a minute.
        #expect(clock.notices.count == 2)
        #expect(clock.notices.allSatisfy { $0.contains("Every sandbox host is busy right now. (fleet_busy)") })
        #expect(clock.notices.first?.contains("Waiting up to 5 minutes") == true)
        #expect(clock.notices.last?.contains("after 1 min") == true)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func waitTimeoutFailsWithFleetBusyAtItsDeadline() async throws {
        let clock = FakeClock()
        givenCreates([.failure(Self.fleetBusy)], clock: clock)

        await #expect(throws: Self.fleetBusy) { try await create(clock: clock, waitTimeout: "5m") }

        // About two creates a minute, well under the account's 10, and none started at or past the deadline.
        #expect(clock.attemptTimes == stride(from: 0, to: 300, by: 30).map { TimeInterval($0) })
        #expect(clock.elapsed <= 300)
        #expect(clock.notices.count == 5)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [
        SandboxesServiceError.refused(SandboxServerError(message: "The account's limit.", code: "account_limit")),
        SandboxesServiceError.refused(SandboxServerError(message: "Too many creates.", code: "rate_limited")),
        SandboxesServiceError.unavailable(SandboxServerError(message: "The node went away.", code: "node_disconnected")),
        SandboxesServiceError.unavailable(SandboxServerError(message: "Busy, says an older server.")),
        SandboxesServiceError.unknownError(502),
    ])
    func waitTimeoutRetriesNothingButFleetBusy(error: SandboxesServiceError) async throws {
        let clock = FakeClock()
        givenCreates([.failure(error), .success(Self.sandbox(status: "active"))], clock: clock)

        await #expect(throws: error) { try await create(clock: clock, waitTimeout: "5m") }

        #expect(clock.attemptTimes == [0])
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func createWithoutAWaitTimeoutLeavesFleetBusyToTheCaller() async throws {
        let clock = FakeClock()
        givenCreates([.failure(Self.fleetBusy), .success(Self.sandbox(status: "active"))], clock: clock)

        await #expect(throws: Self.fleetBusy) { try await create(clock: clock, waitTimeout: nil) }

        #expect(clock.attemptTimes == [0])
        #expect(clock.notices.isEmpty)
    }

    @Test
    func waitTimeoutTakesADurationUpToAnHour() throws {
        func seconds(_ value: String) throws -> TimeInterval? {
            try SandboxCreateCommand.parse(["--wait-timeout", value]).waitTimeoutSeconds
        }
        #expect(try seconds("5m") == 300)
        #expect(try seconds("90s") == 90)
        #expect(try seconds("90") == 90)
        #expect(try seconds("1h") == 3600)
        #expect(try SandboxCreateCommand.parse([]).waitTimeoutSeconds == nil)
        for invalid in ["0", "61m", "2h", "5x", "m", "-5m", "1.5m"] {
            #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--wait-timeout", invalid]) }
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
            xcodeVersion: .value(nil),
            vcpus: .value(8),
            memoryMB: .value(24576),
            workspaceGB: .value(nil),
            guaranteedVCPUs: .value(nil),
            lifetimeSeconds: .value(nil)
        ).willReturn(try Self.decode(created))

        let command = try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "8", "--memory-gb", "24"])
        try await subject().create(
            options: Self.values(),
            platform: command.resolvedPlatform.server,
            template: command.template,
            xcodeVersion: command.xcode,
            vcpus: command.vcpus,
            memoryGB: command.memoryGB,
            workspaceGB: command.workspaceGb
        )

        #expect(ui().contains("Platform: macOS"))
        #expect(ui().contains("vCPUs: 8"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func anXcodeVersionAsksForAMacOSSandboxWithIt() async throws {
        let created = Self.sandbox(status: "starting")
            .replacingOccurrences(of: "\"vcpus\":4", with: "\"platform\":\"darwin\",\"vcpus\":8")
        given(sandboxesService).createSandbox(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            platform: .value(.darwin),
            template: .value(nil),
            xcodeVersion: .value("26.1.1"),
            vcpus: .value(nil),
            memoryMB: .value(nil),
            workspaceGB: .value(nil),
            guaranteedVCPUs: .value(nil),
            lifetimeSeconds: .value(nil)
        ).willReturn(try Self.decode(created))

        let command = try SandboxCreateCommand.parse(["--xcode", "26.1.1"])
        try await subject().create(
            options: Self.values(),
            platform: command.resolvedPlatform.server,
            template: command.template,
            xcodeVersion: command.xcode,
            vcpus: command.vcpus,
            memoryGB: command.memoryGB,
            workspaceGB: command.workspaceGb
        )

        #expect(ui().contains("Platform: macOS"))
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--platform", "linux", "--xcode", "26.1.1"]) }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func extendsASandboxsLifetimeInMinutes() async throws {
        let extended = Self.sandbox(status: "active")
            .replacingOccurrences(
                of: "\"vcpus\":4",
                with: "\"vcpus\":4,\"lifetime_seconds\":14400,\"expires_at\":\"2026-11-01T14:00:00Z\""
            )
        given(sandboxesService).extendSandbox(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id),
            lifetimeSeconds: .value(14400)
        ).willReturn(try Self.decode(extended))

        let command = try SandboxExtendCommand.parse([Self.id, "--lifetime-minutes", "240"])
        try await subject().extend(options: Self.values(), sandboxID: Self.id, lifetimeMinutes: command.lifetimeMinutes)

        #expect(ui().contains("Extended sandbox \(Self.id) until"))
        #expect(throws: (any Error).self) { try SandboxExtendCommand.parse([Self.id, "--lifetime-minutes", "0"]) }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func failsWithoutAnAccount() async throws {
        await #expect(throws: SandboxCommandError.missingAccount) {
            try await subject(fullHandle: nil).show(options: Self.values(), sandboxID: Self.id)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func execWithJSONPrintsTheWholeOutputAndExitsWithTheCommandsStatus() async throws {
        let commandID = "6a1c0d2e-3b4f-4a5b-9c6d-7e8f90a1b2c3"
        given(sandboxesService).startSandboxCommand(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id),
            id: .any,
            command: .value("make test"),
            cwd: .value("/work"),
            environment: .value(["CI": "1"]),
            stdin: .value(false),
            timeoutMs: .value(30000)
        ).willReturn(try Self.decode("""
        {"id":"\(commandID)","command":"make test","stdin":false,"status":"running",
         "started_at":"2026-11-08T10:00:00Z","deadline_at":"2026-11-08T11:00:00Z"}
        """) as ServerSandboxCommand)
        let lines = try [
            #"{"type":"stdout","data":"ok\n","offset":3}"#,
            #"{"type":"stderr","data":"1 failure","offset":9}"#,
            #"{"type":"exit","status":"exited","exit_code":2}"#,
        ].map { try JSONDecoder().decode(ServerSandboxCommandLogLine.self, from: Data($0.utf8)) }
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .value(commandID),
            stdoutOffset: .value(0), stderrOffset: .value(0)
        ).willReturn(AsyncThrowingStream { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        })

        await #expect(throws: ExitCode(2)) {
            try await subject().exec(
                options: Self.values(json: true),
                sandboxID: Self.id,
                command: "make test",
                cwd: "/work",
                environment: ["CI": "1"],
                timeoutMs: 30000
            )
        }
        let output = ui()
        let json = try #require(output.firstIndex(of: "{").map { output[$0...] })
        let printed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(printed["stdout"] as? String == "ok\n")
        #expect(printed["stderr"] as? String == "1 failure")
        #expect(printed["exit_code"] as? Int == 2)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func execAttachingWithAWaitContinuesFromTheOffsetsAndReturnsWhereItStoppedWhileTheCommandRuns() async throws {
        let commandID = "6a1c0d2e-3b4f-4a5b-9c6d-7e8f90a1b2c3"
        let open = OpenStreams()
        let line = try JSONDecoder().decode(
            ServerSandboxCommandLogLine.self,
            from: Data(#"{"type":"stdout","data":"Compiling\n","offset":130}"#.utf8)
        )
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .value("resolved-account"), serverURL: .any, sandboxID: .value(Self.id),
            commandID: .value(commandID), stdoutOffset: .value(120), stderrOffset: .value(7)
        ).willReturn(open.stream(AsyncThrowingStream { continuation in
            continuation.yield(line)
            continuation.finish()
        }))

        await #expect(throws: ExitCode(75)) {
            try await subject().exec(
                options: Self.values(json: true),
                sandboxID: Self.id,
                command: "",
                cwd: nil,
                environment: [:],
                timeoutMs: nil,
                waitSeconds: 1,
                attach: commandID,
                offsets: .init(stdout: 120, stderr: 7)
            )
        }
        let output = ui()
        let json = try #require(output.firstIndex(of: "{").map { output[$0...] })
        let printed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(printed["status"] as? String == "running")
        #expect(printed["command_id"] as? String == commandID)
        #expect(printed["stdout"] as? String == "Compiling\n")
        #expect(printed["stdout_offset"] as? Int == 130)
        #expect(printed["stderr_offset"] as? Int == 7)
        #expect(printed["exit_code"] == nil)
        verify(sandboxesService).startSandboxCommand(
            accountHandle: .any, serverURL: .any, sandboxID: .any, id: .any, command: .any, cwd: .any,
            environment: .any, stdin: .any, timeoutMs: .any
        ).called(0)
    }

    private func givenScreenshotCommand(emitting lines: [String]) throws {
        let commandID = "7b2d1e3f-4c5a-4b6c-8d7e-9f0a1b2c3d4e"
        given(sandboxesService).startSandboxCommand(
            accountHandle: .value("resolved-account"),
            serverURL: .value(Self.serverURL),
            sandboxID: .value(Self.id),
            id: .any,
            command: .value(SandboxScreenshot.script),
            cwd: .value(nil),
            environment: .value(["TUIST_TARGET": "simulator", "TUIST_DEVICE": "booted"]),
            stdin: .value(false),
            timeoutMs: .any
        ).willReturn(try Self.decode("""
        {"id":"\(commandID)","command":"","stdin":false,"status":"running",
         "started_at":"2026-11-08T10:00:00Z","deadline_at":"2026-11-08T11:00:00Z"}
        """) as ServerSandboxCommand)
        let decoded = try lines.map { try JSONDecoder().decode(ServerSandboxCommandLogLine.self, from: Data($0.utf8)) }
        given(sandboxesService).streamSandboxCommandLogs(
            accountHandle: .any, serverURL: .any, sandboxID: .any, commandID: .value(commandID),
            stdoutOffset: .any, stderrOffset: .any
        ).willReturn(AsyncThrowingStream { continuation in
            decoded.forEach { continuation.yield($0) }
            continuation.finish()
        })
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    /// A PNG's signature and IHDR chunk, 1179 × 2556 pixels, then the rest of the file.
    private static let png = Data(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
            + [0, 0, 0x04, 0x9B, 0, 0, 0x09, 0xFC, 8, 6, 0, 0, 0]
    ) + Data(repeating: 7, count: 300)

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func screenshotWritesThePNGTheSandboxSentAndReportsItsSize() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = Self.png
        let encoded = png.base64EncodedString(options: .lineLength76Characters)
        // Split mid-line so the header spans two log lines, as a stream can.
        let split = encoded.index(encoded.startIndex, offsetBy: 17)
        try givenScreenshotCommand(emitting: [
            #"{"type":"stdout","data":"\#(encoded[..<split])","offset":17}"#,
            #"{"type":"stderr","data":"Wrote screenshot to: /tmp/x\n","offset":28}"#,
            #"{"type":"stdout","data":"\#(encoded[split...].replacingOccurrences(of: "\r\n", with: "\\n"))","offset":500}"#,
            #"{"type":"exit","status":"exited","exit_code":0}"#,
        ])
        let out = directory.appendingPathComponent("shots/home.png")

        try await subject().screenshot(
            options: Self.values(json: true), sandboxID: Self.id, target: .simulator, device: nil, localPath: out.path
        )

        #expect(FileManager.default.contents(atPath: out.path) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.deletingLastPathComponent().path) == ["home.png"])
        let output = ui()
        let json = try #require(output.firstIndex(of: "{").map { output[$0...] })
        let printed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(printed["path"] as? String == out.path)
        #expect(printed["width"] as? Int == 1179)
        #expect(printed["height"] as? Int == 2556)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func screenshotWithoutABootedSimulatorSaysToBootOneAndLeavesTheDestinationAlone() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let out = directory.appendingPathComponent("home.png")
        FileManager.default.createFile(atPath: out.path, contents: Data("old".utf8))
        try givenScreenshotCommand(emitting: [#"{"type":"exit","status":"exited","exit_code":4}"#])

        await #expect(throws: SandboxCommandError.noBootedSimulator(nil)) {
            try await subject().screenshot(
                options: Self.values(), sandboxID: Self.id, target: .simulator, device: nil, localPath: out.path
            )
        }
        #expect(FileManager.default.contents(atPath: out.path) == Data("old".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["home.png"])
    }

    @Test
    func screenshotNeedsADestinationAndTakesADeviceOnlyForTheSimulator() throws {
        #expect(try SandboxScreenshotCommand.parse([Self.id, "--out", "a.png"]).target == .simulator)
        #expect(try SandboxScreenshotCommand.parse([Self.id, "--screen", "-o", "a.png"]).target == .screen)
        #expect(throws: Never.self) { try SandboxScreenshotCommand.parse([Self.id, "--device", "iPhone 18 Pro", "-o", "a.png"]) }
        #expect(throws: (any Error).self) { try SandboxScreenshotCommand.parse([Self.id]) }
        #expect(throws: (any Error).self) { try SandboxScreenshotCommand.parse([Self.id, "--screen", "--device", "x", "-o", "a"])
        }
    }

    @Test
    func deleteRequiresConfirmationAndCreateRequiresAnOfferedShape() throws {
        #expect(throws: (any Error).self) { try SandboxDeleteCommand.parse([Self.id]) }
        #expect(throws: Never.self) { try SandboxDeleteCommand.parse([Self.id, "--yes"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "4", "--memory-gb", "4"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "4"]) }
        #expect(throws: Never.self) { try SandboxCreateCommand.parse(["--vcpus", "4", "--memory-gb", "8"]) }
        #expect(throws: (any Error).self) { try SandboxCreateCommand.parse(["--vcpus", "8", "--memory-gb", "24"]) }
        #expect(throws: Never.self) {
            try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "8", "--memory-gb", "24"])
        }
        #expect(throws: (any Error).self) {
            try SandboxCreateCommand.parse(["--platform", "macos", "--vcpus", "4", "--memory-gb", "8"])
        }
        #expect(throws: (any Error).self) { try SandboxShowCommand.parse(["not-a-uuid"]) }
    }

    @Test
    func execJoinsTheCommandAfterTheSeparator() throws {
        let command = try SandboxExecCommand.parse([
            Self.id, "--timeout", "3600", "--env", "TOKEN=a=b", "--", "ls", "-la", "/workspace",
        ])
        #expect(command.command == ["ls", "-la", "/workspace"])
        #expect(command.sandbox.sandboxID == Self.id)
        #expect(command.environment == ["TOKEN": "a=b"])
        #expect(throws: (any Error).self) { try SandboxExecCommand.parse([Self.id, "--env", "TOKEN", "--", "ls"]) }
        #expect(throws: (any Error).self) { try SandboxExecCommand.parse([Self.id, "--timeout", "21601", "--", "ls"]) }
        let commandID = "6a1c0d2e-3b4f-4a5b-9c6d-7e8f90a1b2c3"
        #expect(throws: Never.self) {
            try SandboxExecCommand.parse([
                Self.id, "--attach", commandID, "--stdout-offset", "10", "--stderr-offset", "0", "--wait", "100",
            ])
        }
        #expect(throws: (any Error).self) { try SandboxExecCommand.parse([Self.id, "--attach", commandID, "--", "ls"]) }
        #expect(throws: (any Error).self) { try SandboxExecCommand.parse([Self.id, "--stdout-offset", "10", "--", "ls"]) }
        #expect(throws: (any Error).self) { try SandboxExecCommand.parse([Self.id, "--wait", "0", "--", "ls"]) }
    }

    @Test
    func cpTreatsOnlyASandboxIDBeforeTheColonAsTheSandboxSide() throws {
        #expect(SandboxCopyCommand.Location("\(Self.id):/tmp/screen.png") == .sandbox(id: Self.id, path: "/tmp/screen.png"))
        #expect(SandboxCopyCommand.Location("\(Self.id):a:b") == .sandbox(id: Self.id, path: "a:b"))
        #expect(SandboxCopyCommand.Location("build:out/App.app") == .local("build:out/App.app"))
        #expect(SandboxCopyCommand.Location("/tmp/\(Self.id):x") == .local("/tmp/\(Self.id):x"))

        #expect(throws: Never.self) { try SandboxCopyCommand.parse(["\(Self.id):App.app", "."]) }
        #expect(throws: Never.self) { try SandboxCopyCommand.parse(["fixtures", "\(Self.id):work/fixtures"]) }
        #expect(throws: (any Error).self) { try SandboxCopyCommand.parse(["a", "b"]) }
        #expect(throws: (any Error).self) { try SandboxCopyCommand.parse(["\(Self.id):a", "\(Self.id):b"]) }
        #expect(throws: (any Error).self) { try SandboxCopyCommand.parse(["\(Self.id):", "."]) }
    }
}

/// A clock that create attempts and the waits between them move forward, recording when each attempt started.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var attempts: [TimeInterval] = []
    private var recorded: [String] = []

    var now: Date { lock.withLock { current } }
    var elapsed: TimeInterval { lock.withLock { current.timeIntervalSince(start) } }
    var attemptTimes: [TimeInterval] { lock.withLock { attempts } }
    var notices: [String] { lock.withLock { recorded } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    /// Records an attempt now and returns how many came before it.
    func attempt() -> Int {
        lock.withLock {
            attempts.append(current.timeIntervalSince(start))
            return attempts.count - 1
        }
    }

    func notice(_ message: String) {
        lock.withLock { recorded.append(message) }
    }
}
