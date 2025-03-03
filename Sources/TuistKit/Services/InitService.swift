import FileSystem
import Noora
import Path
import ServiceContextModule
import TuistServer
import TuistSupport

public struct InitService {
    private let fileSystem: FileSystem
    private let prompter: InitPrompting
    private let loginService: LoginServicing
    private let createProjectService: CreateProjectServicing
    private let serverSessionController: ServerSessionControlling
    private let startGeneratedProjectService: InitGeneratedProjectServicing
    private let keystrokeListener: KeyStrokeListening

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
        startGeneratedProjectService: InitGeneratedProjectServicing = InitGeneratedProjectService(),
        keystrokeListener: KeyStrokeListening = KeyStrokeListener()
    ) {
        self.fileSystem = fileSystem
        self.prompter = prompter
        self.loginService = loginService
        self.createProjectService = createProjectService
        self.serverSessionController = serverSessionController
        self.startGeneratedProjectService = startGeneratedProjectService
        self.keystrokeListener = keystrokeListener
    }

    func run(from directory: AbsolutePath, answers: InitPromptAnswers?) async throws {
        let tuistSwiftLine: String
        let projectDirectory: AbsolutePath

        switch try await nameOfXcodeProjectOrWorkspace(in: directory, answers: answers) {
        case .createGeneratedProject:
            let name = answers?.generatedProjectName ?? prompter.promptGeneratedProjectName()
            let platform = answers?.generatedProjectPlatform ?? prompter.promptGeneratedProjectPlatform()
            projectDirectory = try await createGeneratedProject(at: directory, name: name, platform: platform)
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(named: name, in: directory, answers: answers) {
                tuistSwiftLine = "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .tuist())"
            } else {
                tuistSwiftLine = "let tuist = Tuist(project: .tuist())"
            }
        case let .integrateWithProjectOrWorkspace(name):
            projectDirectory = directory
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(named: name, in: directory, answers: answers) {
                tuistSwiftLine = "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .xcode())"
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

        ServiceContext.current?.alerts?.success(.alert("You are all set to explore the Tuist universe", nextSteps: [
            "Accelerate your builds with the \(.link(title: "cache", href: "https://docs.tuist.dev/en/guides/develop/cache"))",
            "Accelerate your test runs with \(.link(title: "selective testing", href: "https://docs.tuist.dev/en/guides/develop/selective-testing"))",
            "Accelerate your Swift package resolution with \(.link(title: "the registry", href: "https://docs.tuist.dev/en/guides/develop/registry"))",
            "Share your app easily with \(.link(title: "previews", href: "https://docs.tuist.dev/en/guides/share/previews"))",
        ]))
    }

    private func createGeneratedProject(at directory: AbsolutePath, name: String, platform: String) async throws -> AbsolutePath {
        let projectDirectory = directory.appending(component: name)
        try await ServiceContext.current?.ui?.progressStep(
            message: "Creating generated project",
            successMessage: "Generated project created",
            errorMessage: "Failed to create generated project",
            showSpinner: true,
            task: { _ in
                if !(try await fileSystem.exists(projectDirectory)) {
                    try await fileSystem.makeDirectory(at: projectDirectory)
                }
                try await startGeneratedProjectService.run(
                    name: name,
                    platform: platform,
                    path: projectDirectory.pathString,
                    templateName: "default"
                )
            }
        )
        return projectDirectory
    }

    private func integrateWithXcodeProjectOrWorkspace(
        named projectHandle: String,
        in directory: AbsolutePath,
        answers: InitPromptAnswers?
    ) async throws -> String? {
        let integrateWithServer = answers?.integrateWithServer ?? prompter.promptIntegrateWithServer()
        if integrateWithServer {
            try await ServiceContext.current?.ui?.collapsibleStep(
                title: "Authentication",
                successMessage: "Authenticated",
                errorMessage: "Authentication failed",
                visibleLines: 3,
                task: { progress in
                    try await loginService.run(email: nil, password: nil, directory: nil) { event in
                        switch event {
                        case let .openingBrowser(url):
                            await withCheckedContinuation { continuation in
                                progress("Press ENTER to open \(url) in your browser to authenticate...")
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

            let accountHandle = try await serverSessionController.whoami(serverURL: Constants.URLs.production)!
            let fullHandle = "\(accountHandle)/\(projectHandle)"

            try await ServiceContext.current?.ui?.progressStep(
                message: "Creating Tuist project",
                successMessage: "Project connected",
                errorMessage: "Project connection failed",
                showSpinner: true,
                task: { _ in
                    _ = try await createProjectService.createProject(fullHandle: fullHandle, serverURL: Constants.URLs.production)
                }
            )

            return fullHandle
        }

        return nil
    }

    private func nameOfXcodeProjectOrWorkspace(
        in directory: AbsolutePath,
        answers: InitPromptAnswers?
    ) async throws -> InitPromptingWorkflowType {
        let xcodeProjectsAndWorkspaces = try await findXcodeProjectsAndWorkspaces(in: directory)
        return answers?.workflowType ?? prompter
            .promptWorkflowType(
                xcodeProjectOrWorkspace: xcodeProjectsAndWorkspaces
                    .first(where: \.isWorkspace) ?? xcodeProjectsAndWorkspaces.first(where: \.isProject)
            )
    }

    private func findXcodeProjectsAndWorkspaces(in directory: AbsolutePath) async throws -> Set<XcodeProjectOrWorkspace> {
        var paths = Set(
            try await fileSystem.glob(directory: directory, include: ["**/*.xcworkspace"]).collect()
                .filter { $0.parentDirectory.extension != "xcodeproj" }
                .map(XcodeProjectOrWorkspace.workspace)
        )
        paths
            .formUnion(
                try await fileSystem.glob(directory: directory, include: ["**/*.xcodeproj"]).collect()
                    .map(XcodeProjectOrWorkspace.project)
            )
        return paths
    }
}
