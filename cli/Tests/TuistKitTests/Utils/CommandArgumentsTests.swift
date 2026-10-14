import ArgumentParser
import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistBuildCommand
import TuistCacheCommand
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGenerateCommand
import TuistSupport
import TuistTestCommand

@testable import TuistKit

struct CommandArgumentsTests {
    enum Invocation: CaseIterable {
        case generate, generateRun, cache, cacheWarm, edit, install, build, buildRun, test, testRun

        var arguments: [String] {
            switch self {
            case .generate: ["generate"]
            case .generateRun: ["generate", "run"]
            case .cache: ["cache"]
            case .cacheWarm: ["cache", "warm"]
            case .edit: ["edit"]
            case .install: ["install"]
            case .build: ["build"]
            case .buildRun: ["build", "run"]
            case .test: ["test"]
            case .testRun: ["test", "run"]
            }
        }

        var environmentKey: String {
            switch self {
            case .generate, .generateRun: "TUIST_GENERATE_PATH"
            case .cache, .cacheWarm: "TUIST_CACHE_PATH"
            case .edit: "TUIST_EDIT_PATH"
            case .install: "TUIST_INSTALL_PATH"
            case .build, .buildRun: "TUIST_BUILD_OPTIONS_PATH"
            case .test, .testRun: "TUIST_TEST_PATH"
            }
        }
    }

    @Test(.withMockedEnvironment(), arguments: Invocation.allCases)
    func path_uses_the_commands_environment_default(_ invocation: Invocation) async throws {
        let environment = try #require(Environment.mocked)
        for command in Invocation.allCases {
            environment.variables[command.environmentKey] = "/projects/\(command.environmentKey)"
        }
        let command = try ProjectCommandsRoot.parseAsRoot(invocation.arguments)
        let projectCommand = try #require(command as? ProjectPathProviding)

        let path = try await CommandArguments.path(in: invocation.arguments, command: command)

        #expect(projectCommand.path == "/projects/\(invocation.environmentKey)")
        #expect(path == AbsolutePath("/projects/\(invocation.environmentKey)"))
    }

    @Test(
        .withMockedEnvironment(),
        arguments: Invocation.allCases,
        [["--path", "/explicit"], ["-p", "/explicit"], ["--path=/explicit"]]
    )
    func explicit_path_overrides_the_environment(_ invocation: Invocation, _ pathArguments: [String]) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables[invocation.environmentKey] = "/environment"
        let arguments = invocation.arguments + pathArguments
        let command = try ProjectCommandsRoot.parseAsRoot(arguments)

        let path = try await CommandArguments.path(in: arguments, command: command)

        #expect(path == AbsolutePath("/explicit"))
    }

    @Test(.withMockedEnvironment(), arguments: Invocation.allCases)
    func path_defaults_to_the_working_directory(_ invocation: Invocation) async throws {
        let command = try ProjectCommandsRoot.parseAsRoot(invocation.arguments)

        let path = try await CommandArguments.path(in: invocation.arguments, command: command)

        #expect(path == (try await Environment.current.currentWorkingDirectory()))
    }

    @Test(.withMockedEnvironment(), arguments: Invocation.allCases)
    func relative_environment_path_is_resolved_from_the_working_directory(_ invocation: Invocation) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables[invocation.environmentKey] = "app"
        let command = try ProjectCommandsRoot.parseAsRoot(invocation.arguments)

        let path = try await CommandArguments.path(in: invocation.arguments, command: command)

        #expect(path == (try await environment.currentWorkingDirectory()).appending(component: "app"))
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory)
    func configuration_is_loaded_from_the_environment_project_path() async throws {
        let environment = try #require(Environment.mocked)
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDirectory = directory.appending(component: "app")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: projectDirectory)
        try await fileSystem.writeText("project = \"tuist/app\"", at: projectDirectory.appending(component: "tuist.toml"))
        environment.variables["TUIST_GENERATE_PATH"] = projectDirectory.pathString
        let command = try ProjectCommandsRoot.parseAsRoot(["generate"])

        let path = try await CommandArguments.path(in: ["generate"], command: command)
        let config = try await ConfigLoader().loadConfig(path: path)

        #expect(config.fullHandle == "tuist/app")
    }

    @Test(
        .withMockedEnvironment(),
        arguments: [Invocation.install, .build, .buildRun, .test, .testRun],
        [false, true]
    )
    func passthrough_path_does_not_override_the_parsed_project_path(
        _ invocation: Invocation,
        hasEnvironmentPath: Bool
    ) async throws {
        let environment = try #require(Environment.mocked)
        if hasEnvironmentPath {
            environment.variables[invocation.environmentKey] = "/environment"
        }
        let arguments = invocation.arguments + ["--", "--path", "/passthrough"]
        let command = try ProjectCommandsRoot.parseAsRoot(arguments)
        let projectCommand = try #require(command as? ProjectPathProviding)

        let path = try await CommandArguments.path(in: arguments, command: command)

        #expect(projectCommand.path == (hasEnvironmentPath ? "/environment" : nil))
        let workingDirectory = try await environment.currentWorkingDirectory()
        #expect(path == (hasEnvironmentPath ? AbsolutePath("/environment") : workingDirectory))
        if let installCommand = command as? InstallCommand {
            #expect(installCommand.passthroughArguments == ["--", "--path", "/passthrough"])
        }
    }

    @Test(.withMockedEnvironment())
    func nonconforming_commands_keep_raw_argument_path_resolution() async throws {
        let command = OtherCommand()

        let path = try await CommandArguments.path(in: ["other", "-p", "app"], command: command)

        #expect(path == (try await Environment.current.currentWorkingDirectory()).appending(component: "app"))
    }

    @Test(.withMockedEnvironment())
    func plugin_dispatch_keeps_raw_argument_path_resolution() async throws {
        let path = try await CommandArguments.path(in: ["plugin-command", "--path", "/plugin"])

        #expect(path == AbsolutePath("/plugin"))
    }

    @Test(.withMockedEnvironment())
    func unrelated_commands_ignore_project_path_environment_variables() async throws {
        let environment = try #require(Environment.mocked)
        for command in Invocation.allCases {
            environment.variables[command.environmentKey] = "/environment"
        }

        let path = try await CommandArguments.path(in: ["other"], command: OtherCommand())

        #expect(path == (try await environment.currentWorkingDirectory()))
    }
}

private struct ProjectCommandsRoot: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuist",
            subcommands: [
                GenerateCommand.self,
                CacheCommand.self,
                EditCommand.self,
                InstallCommand.self,
                BuildCommand.self,
                TestCommand.self,
            ]
        )
    }
}

private struct OtherCommand: ParsableCommand {}
