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
        name: .long,
        help:
        "The workflow to run non-interactively. One of 'generated' (create a Tuist-generated Xcode project), 'xcode' (integrate an existing Xcode project or workspace), 'gradle' (integrate a Gradle project), or 'bazel' (integrate a Bazel workspace). When set, all remaining prompts are answered from the other flags."
    )
    var workflow: String?

    @Option(
        name: .long,
        help:
        "The project name. For 'generated' this is the directory name and the server project handle. For 'xcode' and 'gradle' this is the server project handle."
    )
    var name: String?

    @Option(
        name: .long,
        help:
        "The platform for a 'generated' project. One of 'ios', 'macos', 'tvos', 'watchos'."
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

        // Otherwise, compose from the ergonomic flags. `--workflow` opts in — if
        // it isn't set, everything falls back to the interactive prompter and
        // the other flags are ignored.
        guard let workflow else { return nil }

        if account != nil, createOrganization != nil {
            throw ValidationError("--account and --create-organization are mutually exclusive.")
        }

        let workflowType = try resolvedWorkflowType(from: workflow)

        if server, account == nil, createOrganization == nil {
            throw ValidationError(
                "--account or --create-organization is required when the server integration is enabled. Pass --no-server to skip."
            )
        }

        switch workflowType {
        #if os(macOS)
            case .createGeneratedProject:
                guard name != nil else {
                    throw ValidationError("--name is required for --workflow generated.")
                }
                guard platform != nil else {
                    throw ValidationError(
                        "--platform is required for --workflow generated. One of: ios, macos, tvos, watchos."
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
                // we pick here doesn't affect behavior — `.organization` is the
                // safer default since the service doesn't verify membership.
                .organization(account)
            } else {
                .organization("")
            }

        return InitPromptAnswers(
            workflowType: workflowType,
            integrateWithServer: server,
            generatedProjectPlatform: platform ?? "",
            generatedProjectName: name ?? "",
            accountType: accountType,
            newOrganizationAccountHandle: createOrganization ?? ""
        )
    }

    private func resolvedWorkflowType(from workflow: String) throws
        -> InitPromptingWorkflowType
    {
        switch workflow.lowercased() {
        #if os(macOS)
            case "generated":
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
                    "Unknown --workflow '\(workflow)'. Expected one of: generated, xcode, gradle, bazel."
                )
            #else
                throw ValidationError(
                    "Unknown --workflow '\(workflow)'. Expected one of: gradle, bazel."
                )
            #endif
        }
    }
}
