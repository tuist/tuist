import ArgumentParser
import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistNooraExtension

public struct InitCommand: AsyncParsableCommand, NooraReadyCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init",
            abstract: "Get started with Tuist in your project."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory from where to start.",
        completion: .directory,
        envKey: .initPath
    )
    var path: String?

    @Option(
        name: [.customLong("build-system"), .customLong("workflow")],
        help:
        "The build system to integrate with, non-interactively. One of 'xcode' (integrate an existing Xcode project or workspace), 'generated-xcode' (create a Tuist-generated Xcode project), 'gradle' (integrate a Gradle project), or 'bazel' (integrate a Bazel workspace). When set, all remaining prompts are answered from the other flags. `--workflow` is accepted as an alias."
    )
    var buildSystem: String?

    @Option(
        name: .long,
        help:
        "The project name. Also the server project handle. Defaults to the current directory name."
    )
    var name: String?

    @Option(
        name: .long,
        help:
        "The platform for a 'generated-xcode' project. One of 'ios', 'macos', 'tvos', 'watchos'."
    )
    var platform: String?

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help:
        "Integrate with the Tuist server (create/select a project so features like caching and insights can flow). Defaults to true."
    )
    var server: Bool = true

    @Option(
        name: .long,
        help:
        "The handle of the account that should own the project. Must be your handle or an organization you belong to."
    )
    var account: String?

    @Option(
        name: .long,
        help:
        "Create a new organization with this handle and use it as the project owner. Mutually exclusive with --account."
    )
    var createOrganization: String?

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp("Base64-encoded prompt answers", visibility: .private),
        completion: nil,
        envKey: .initPath
    )
    var answers: String?

    public var jsonThroughNoora: Bool = false

    public init() {}

    public func run() async throws {
        try await InitCommandService().run(
            from: try await Environment.current.pathRelativeToWorkingDirectory(path),
            answers: try await composedAnswers()
        )
    }

    private func composedAnswers() async throws -> InitPromptAnswers? {
        // The `--answers` private escape hatch takes precedence when set.
        if let answersBase64String = answers {
            guard let jsonData = Data(base64Encoded: answersBase64String) else { return nil }
            return try? JSONDecoder().decode(InitPromptAnswers.self, from: jsonData)
        }

        // Otherwise, compose from the ergonomic flags. `--build-system` opts in.
        // If it isn't set, the interactive prompter drives everything, and the
        // other non-interactive flags are meaningless — raise instead of
        // silently ignoring them so misconfigured invocations don't run.
        guard let buildSystem else {
            let leftover = nonInteractiveFlagsWithoutBuildSystem()
            if !leftover.isEmpty {
                throw ValidationError(
                    "--build-system is required when \(leftover.joined(separator: ", ")) is passed. Pick one of: xcode, generated-xcode, gradle, bazel."
                )
            }
            return nil
        }

        if account != nil, createOrganization != nil {
            throw ValidationError("--account and --create-organization are mutually exclusive.")
        }

        let workflowType = try resolvedWorkflowType(from: buildSystem)

        if server, account == nil, createOrganization == nil {
            throw ValidationError(
                "--account or --create-organization is required when the server integration is enabled. Pass --no-server to skip."
            )
        }

        guard let projectName = name else {
            throw ValidationError(
                "--name is required when --build-system is set. Pass the server project handle to use."
            )
        }

        switch workflowType {
        #if os(macOS)
            case .createGeneratedProject:
                guard platform != nil else {
                    throw ValidationError(
                        "--platform is required for --build-system generated-xcode. One of: ios, macos, tvos, watchos."
                    )
                }
            case .connectProjectOrSwiftPackage:
                break
        #endif
        case .connectGradleProject:
            break
        case .connectBazelWorkspace:
            break
        }

        let accountType: InitPromptingAccountType =
            if let createOrganization {
                .createOrganizationAccount
            } else if let account {
                // The `case let .userAccount(handle), let .organization(handle)`
                // path in the service returns `handle` for both, so which case
                // we pick here doesn't affect behavior; `.organization` is the
                // safer default since the service doesn't verify membership.
                .organization(account)
            } else {
                .organization("")
            }

        return InitPromptAnswers(
            workflowType: workflowType,
            integrateWithServer: server,
            generatedProjectPlatform: platform ?? "",
            generatedProjectName: projectName,
            accountType: accountType,
            newOrganizationAccountHandle: createOrganization ?? ""
        )
    }

    private func nonInteractiveFlagsWithoutBuildSystem() -> [String] {
        var flags: [String] = []
        if name != nil { flags.append("--name") }
        if platform != nil { flags.append("--platform") }
        if account != nil { flags.append("--account") }
        if createOrganization != nil { flags.append("--create-organization") }
        // `server` is a flag with a default, not an optional; only report it
        // when the user explicitly opted out.
        if !server { flags.append("--no-server") }
        return flags
    }

    private func resolvedWorkflowType(from buildSystem: String) throws
        -> InitPromptingWorkflowType
    {
        switch buildSystem.lowercased() {
        #if os(macOS)
            // Accept both the new "generated-xcode" spelling and the previous
            // "generated" alias so early copies of the flag keep working.
            case "generated-xcode", "generated":
                return .createGeneratedProject
            case "xcode":
                return .connectProjectOrSwiftPackage(name)
        #endif
        case "gradle":
            return .connectGradleProject
        case "bazel":
            return .connectBazelWorkspace
        default:
            #if os(macOS)
                throw ValidationError(
                    "Unknown --build-system '\(buildSystem)'. Expected one of: xcode, generated-xcode, gradle, bazel."
                )
            #else
                throw ValidationError(
                    "Unknown --build-system '\(buildSystem)'. Expected one of: gradle, bazel."
                )
            #endif
        }
    }
}
