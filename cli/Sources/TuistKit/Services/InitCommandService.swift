import Command
import FileSystem
import Foundation
import Noora
import Path
import TuistServer
import TuistSupport

public enum InitCommandServiceError: LocalizedError {
    case emptyProjectHandle

    public var errorDescription: String? {
        switch self {
        case .emptyProjectHandle:
            return "The project handel introduced is empty."
        }
    }
}

public struct InitCommandService {
    private let fileSystem: FileSystem
    private let prompter: InitPrompting
    private let loginService: LoginServicing
    private let createProjectService: CreateProjectServicing
    private let createOrganizationService: CreateOrganizationServicing
    private let listOrganizationsService: ListOrganizationsServicing
    private let serverSessionController: ServerSessionControlling
    private let initGeneratedProjectService: InitGeneratedProjectServicing
    private let keystrokeListener: KeyStrokeListening
    private let getProjectService: GetProjectServicing
    private let commandRunner: CommandRunning
    private let serverEnvironmentService: ServerEnvironmentServicing

    enum XcodeProjectOrWorkspace: Hashable, Equatable {
        case workspace(AbsolutePath)
        case project(AbsolutePath)

        var isWorkspace: Bool {
            switch self {
            case .workspace: true
            case .project: false
            }
        }

        var isProject: Bool {
            switch self {
            case .workspace: false
            case .project: true
            }
        }

        var name: String {
            switch self {
            case let .project(path): return path.basenameWithoutExt
            case let .workspace(path): return path.basenameWithoutExt
            }
        }
    }

    init(
        fileSystem: FileSystem = FileSystem(),
        prompter: InitPrompting = InitPrompter(),
        loginService: LoginServicing = LoginService(),
        createProjectService: CreateProjectServicing = CreateProjectService(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        initGeneratedProjectService: InitGeneratedProjectServicing = InitGeneratedProjectService(),
        keystrokeListener: KeyStrokeListening = KeyStrokeListener(),
        createOrganizationService: CreateOrganizationServicing = CreateOrganizationService(),
        listOrganizationsService: ListOrganizationsServicing = ListOrganizationsService(),
        getProjectService: GetProjectServicing = GetProjectService(),
        commandRunner: CommandRunning = CommandRunner(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.fileSystem = fileSystem
        self.prompter = prompter
        self.loginService = loginService
        self.createProjectService = createProjectService
        self.serverSessionController = serverSessionController
        self.initGeneratedProjectService = initGeneratedProjectService
        self.keystrokeListener = keystrokeListener
        self.createOrganizationService = createOrganizationService
        self.listOrganizationsService = listOrganizationsService
        self.getProjectService = getProjectService
        self.commandRunner = commandRunner
        self.serverEnvironmentService = serverEnvironmentService
    }

    func run(from directory: AbsolutePath, answers: InitPromptAnswers?) async throws {
        let tuistSwiftLine: String
        let projectDirectory: AbsolutePath

        var nextSteps: [TerminalText] = []

        switch try await nameOfXcodeProjectOrWorkspace(in: directory, answers: answers) {
        case .createGeneratedProject:
            nextSteps.append("Generate your project with \(.command("tuist generate"))")
            nextSteps.append("Visualize your project graph with \(.command("tuist graph"))")

            let name = answers?.generatedProjectName ?? prompter.promptGeneratedProjectName()
            let platform =
                answers?.generatedProjectPlatform ?? prompter.promptGeneratedProjectPlatform()
            projectDirectory = try await createGeneratedProject(
                at: directory, name: name, platform: platform
            )
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(
                named: name,
                in: directory,
                answers: answers,
                nextSteps: &nextSteps
            ) {
                tuistSwiftLine =
                    "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .tuist())"
            } else {
                tuistSwiftLine = "let tuist = Tuist(project: .tuist())"
            }
        case let .connectProjectOrSwiftPackage(name):
            projectDirectory = directory
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(
                named: name ?? projectDirectory.basename,
                in: directory,
                answers: answers,
                nextSteps: &nextSteps
            ) {
                tuistSwiftLine =
                    "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .xcode())"
            } else {
                tuistSwiftLine = "let tuist = Tuist(project: .xcode())"
            }
        }

        let tuistSwiftFileContent = """
        import ProjectDescription

        \(tuistSwiftLine)
        """
        let tuistSwiftFilePath = projectDirectory.appending(component: "Tuist.swift")
        if try await fileSystem.exists(tuistSwiftFilePath) {
            try await fileSystem.remove(tuistSwiftFilePath)
        }
        try await fileSystem.writeText(tuistSwiftFileContent, at: tuistSwiftFilePath)

        try await mise(path: projectDirectory, nextSteps: &nextSteps)

        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if projectDirectory != currentWorkingDirectory {
            nextSteps.insert(
                "Choose the project directory with \(.command("cd \(projectDirectory.relative(to: currentWorkingDirectory).pathString)"))",
                at: 0
            )
        }

        AlertController.current.success(
            .alert("You are all set to explore the Tuist universe", takeaways: nextSteps)
        )
    }

    private func mise(path: AbsolutePath, nextSteps _: inout [TerminalText]) async throws {
        let version = (Constants.version == "x.y.z") ? "latest" : Constants.version
        try? await commandRunner.run(
            arguments: [
                "/usr/bin/env",
                "mise",
                "use",
                "tuist@\(version!)",
                "--path",
                path.appending(component: "mise.toml").pathString,
            ],
            workingDirectory: path
        ).awaitCompletion()
    }

    private func createGeneratedProject(at directory: AbsolutePath, name: String, platform: String)
        async throws -> AbsolutePath
    {
        let projectDirectory = directory.appending(component: name)
        try await Noora.current.progressStep(
            message: "Creating generated project",
            successMessage: "Generated project created",
            errorMessage: "Failed to create generated project",
            showSpinner: true,
            task: { _ in
                if !(try await fileSystem.exists(projectDirectory)) {
                    try await fileSystem.makeDirectory(at: projectDirectory)
                }
                try await initGeneratedProjectService.run(
                    name: name,
                    platform: platform,
                    path: projectDirectory.pathString
                )
            }
        )
        return projectDirectory
    }

    private func integrateWithXcodeProjectOrWorkspace(
        named projectHandle: String,
        in _: AbsolutePath,
        answers: InitPromptAnswers?,
        nextSteps: inout [TerminalText]
    ) async throws -> String? {
        let integrateWithServer =
            answers?.integrateWithServer ?? prompter.promptIntegrateWithServer()
        if integrateWithServer {
            let serverURL = try serverEnvironmentService.url(configServerURL: Constants.URLs.production)
            if try await serverSessionController.whoami(serverURL: serverURL) == nil {
                try await Noora.current.collapsibleStep(
                    title: "Authentication",
                    successMessage: "Authenticated",
                    errorMessage: "Authentication failed",
                    visibleLines: 3,
                    task: { progress in
                        try await loginService.run(email: nil, password: nil, directory: nil) {
                            event in
                            switch event {
                            case let .openingBrowser(url):
                                await withCheckedContinuation { continuation in
                                    progress(
                                        "Press ENTER to open \(url) in your browser to authenticate..."
                                    )
                                    keystrokeListener.listen { key in
                                        switch key {
                                        case .returnKey:
                                            continuation.resume()
                                            return .abort
                                        default:
                                            return .continue
                                        }
                                    }
                                }
                            default:
                                progress("\(event.description)")
                            }
                        }
                    }
                )
            }
            let fullHandle =
                "\(try await accountHandle(answers: answers, serverURL: serverURL))/\(projectHandle)"

            if fullHandle == "" {
                throw InitCommandServiceError.emptyProjectHandle
            }

            try await Noora.current.progressStep(
                message: "Creating Tuist project",
                successMessage: "Project connected",
                errorMessage: "Project connection failed",
                showSpinner: true,
                task: { _ in
                    if (try? await getProjectService.getProject(
                        fullHandle: fullHandle, serverURL: serverURL
                    )) == nil {
                        _ = try await createProjectService.createProject(
                            fullHandle: fullHandle,
                            serverURL: serverURL
                        )
                    }
                }
            )

            nextSteps.append(contentsOf: [
                "Accelerate your builds with the \(.link(title: "cache", href: "https://docs.tuist.dev/en/guides/features/cache"))",
                "Accelerate your test runs with \(.link(title: "selective testing", href: "https://docs.tuist.dev/en/guides/features/selective-testing"))",
                "Accelerate your Swift package resolution with \(.link(title: "the registry", href: "https://docs.tuist.dev/en/guides/features/registry"))",
                "Share your app easily with \(.link(title: "previews", href: "https://docs.tuist.dev/en/guides/features/previews"))",
            ])

            return fullHandle
        } else {
            nextSteps.append(contentsOf: [
                "Learn more about how our \(.link(title: "platform capabilities", href: "https://docs.tuist.dev/en/"))",
            ])
        }

        return nil
    }

    private func accountHandle(
        answers: InitPromptAnswers?,
        serverURL: URL
    ) async throws -> String {
        let accountHandle = try await serverSessionController.whoami(serverURL: serverURL)!
        let organizations =
            (try? await listOrganizationsService.listOrganizations(serverURL: serverURL)) ?? []
        switch answers?.accountType
            ?? prompter.promptAccountType(
                authenticatedUserHandle: accountHandle,
                organizations: organizations
            )
        {
        case .createOrganizationAccount:
            let organizationHandle =
                answers?.newOrganizationAccountHandle
                    ?? prompter.promptNewOrganizationAccountHandle()
            _ = try await createOrganizationService.createOrganization(
                name: organizationHandle,
                serverURL: serverURL
            )
            return organizationHandle
        case let .userAccount(handle),
             let .organization(handle):
            return handle
        }
    }

    private func nameOfXcodeProjectOrWorkspace(
        in directory: AbsolutePath,
        answers: InitPromptAnswers?
    ) async throws -> InitPromptingWorkflowType {
        let xcodeProjectsAndWorkspaces = try await findXcodeProjectsAndWorkspaces(in: directory)
        return answers?.workflowType
            ?? prompter
            .promptWorkflowType(
                xcodeProjectOrWorkspace:
                xcodeProjectsAndWorkspaces
                    .first(where: \.isWorkspace)
                    ?? xcodeProjectsAndWorkspaces.first(where: \.isProject)
            )
    }

    private func findXcodeProjectsAndWorkspaces(in directory: AbsolutePath) async throws -> Set<
        XcodeProjectOrWorkspace
    > {
        var paths = Set(
            try await fileSystem.glob(directory: directory, include: ["*.xcworkspace"]).collect()
                .filter { $0.parentDirectory.extension != "xcodeproj" }
                .map(XcodeProjectOrWorkspace.workspace)
        )
        paths
            .formUnion(
                try await fileSystem.glob(directory: directory, include: ["*.xcodeproj"]).collect()
                    .map(XcodeProjectOrWorkspace.project)
            )
        return paths
    }
}
