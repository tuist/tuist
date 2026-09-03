import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistAlert
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGenerateCommand
import TuistKit
import TuistSupport
import TuistTestCommand
import TuistTesting

/// Both commands consult the gate.
///
/// The gate hangs off several paths that each return before the next, so a run can execute
/// every test it was asked to and still never consult it, which is the regression these
/// cover. The project is bound to a server that refuses connections, and the gate is the only
/// thing that asks that server for a verdict, so its "could not fetch" warning is proof the
/// wiring reached it. No stub and no network are involved in producing it.
private enum StressGateProbe {
    /// Nothing listens on port 1, so the request fails at connect instead of hanging.
    static let unreachableServer = "http://127.0.0.1:1"

    /// Places the fixture where the run will look for it and binds it to the dead server.
    ///
    /// The fixture goes in the working directory rather than staying where the trait copied
    /// it: `tuist xcodebuild test` takes no `--path` at all, and `tuist test` parses its
    /// result bundle only after locating the project root from the working directory, so a
    /// fixture anywhere else leaves the gate with no summary and it skips before asking.
    static func prepareFixture(_ fixtureDirectory: AbsolutePath) async throws -> AbsolutePath {
        let fileSystem = FileSystem()
        let workingDirectory = try await Environment.current.currentWorkingDirectory()
        if try await fileSystem.exists(workingDirectory) {
            try await fileSystem.remove(workingDirectory)
        }
        try await fileSystem.copy(fixtureDirectory, to: workingDirectory)

        // The CLI refuses to talk to a server without a token, and pinning the cache endpoint
        // keeps the run from resolving the account's endpoints, which it treats as fatal.
        Environment.mocked?.variables["TUIST_TOKEN"] = "acceptance-test-token"
        Environment.mocked?.variables["TUIST_CACHE_ENDPOINT"] = unreachableServer

        try await fileSystem.writeText(
            """
            import ProjectDescription

            let tuist = Tuist(fullHandle: "tuist/acceptance", url: "\(unreachableServer)")
            """,
            at: workingDirectory.appending(component: "Tuist.swift"),
            options: Set([.overwrite])
        )
        return workingDirectory
    }

    static func expectTheGateAskedForAVerdict(sourceLocation: SourceLocation = #_sourceLocation) {
        let warnings = AlertController.current.warnings().map { "\($0)" }
        #expect(
            warnings.contains { $0.contains("stress gate verdict") },
            "The gate never asked for a verdict. Warnings: \(warnings)",
            sourceLocation: sourceLocation
        )
    }
}

struct StressNewTestsTestCommandAcceptanceTests {
    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH", "DEVELOPER_DIR"]),
        .withMockedLogger()
    ) func tuist_test_consults_the_gate() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let projectDirectory = try await StressGateProbe.prepareFixture(fixtureDirectory)

        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--stress-new-tests", "report",
                "--path", projectDirectory.pathString,
                "--result-bundle-path", projectDirectory.appending(component: "run.xcresult").pathString,
                "--",
                "-destination", "platform=macOS",
            ]
        )

        StressGateProbe.expectTheGateAskedForAVerdict()
    }
}

struct StressNewTestsXcodeBuildCommandAcceptanceTests {
    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH", "DEVELOPER_DIR"]),
        .withMockedLogger()
    ) func tuist_xcodebuild_test_consults_the_gate() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let projectDirectory = try await StressGateProbe.prepareFixture(fixtureDirectory)

        try await TuistTest.run(
            GenerateCommand.self,
            ["--no-open", "--path", projectDirectory.pathString]
        )

        try await TuistTest.run(
            XcodeBuildTestCommand.self,
            [
                "--stress-new-tests", "report",
                "-workspace", projectDirectory.appending(component: "App.xcworkspace").pathString,
                "-scheme", "MacFrameworkTests",
                "-destination", "platform=macOS",
                "-resultBundlePath", projectDirectory.appending(component: "run.xcresult").pathString,
            ]
        )

        StressGateProbe.expectTheGateAskedForAVerdict()
    }
}
