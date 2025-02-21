import FileSystem
import Noora
import Path
import ServiceContextModule
import TuistServer
import TuistSupport

public struct StartService {
    let fileSystem: FileSystem
    let prompter: StartPrompting
    let loginService: LoginServicing
    let createProjectService: CreateProjectServicing
    let serverSessionController: ServerSessionControlling
    let startGeneratedProjectService: StartGeneratedProjectService

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
        prompter: StartPrompting = StartPrompter(),
        loginService: LoginServicing = LoginService(),
        createProjectService: CreateProjectServicing = CreateProjectService(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        startGeneratedProjectService: StartGeneratedProjectService = StartGeneratedProjectService()
    ) {
        self.fileSystem = fileSystem
        self.prompter = prompter
        self.loginService = loginService
        self.createProjectService = createProjectService
        self.serverSessionController = serverSessionController
        self.startGeneratedProjectService = startGeneratedProjectService
    }

    public func run(from directory: AbsolutePath) async throws {
        let tuistSwiftLine: String
        let projectDirectory: AbsolutePath

        switch try await nameOfXcodeProjectOrWorkspace(in: directory) {
        case .createGeneratedProject:
            let name = prompter.promptGeneratedProjectName()!
            let platform = prompter.promptGeneratedProjectPlatform()!
            projectDirectory = try await createGeneratedProject(at: directory, name: name, platform: platform)
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(named: name, in: directory) {
                tuistSwiftLine = "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .tuist())"
            } else {
                tuistSwiftLine = "let tuist = Tuist(project: .tuist())"
            }
        case let .integrateWithProjectOrWorkspace(name):
            projectDirectory = directory
            if let fullHandle = try await integrateWithXcodeProjectOrWorkspace(named: name, in: directory) {
                tuistSwiftLine = "let tuist = Tuist(fullHandle: \"\(fullHandle)\", project: .xcode)"
            } else {
                tuistSwiftLine = "let tuist = Tuist(project: .xcode)"
            }
        }

        let tuistSwiftFileContent = """
        import ProjectDescription

        \(tuistSwiftLine)
        """
        let tuistSwiftFilePath = directory.appending(component: "Tuist.swift")
        if try await fileSystem.exists(tuistSwiftFilePath) {
            try await fileSystem.remove(tuistSwiftFilePath)
        }
        try await fileSystem.writeText(tuistSwiftFileContent, at: tuistSwiftFilePath)
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
                    templateName: "default",
                    requiredTemplateOptions: [:],
                    optionalTemplateOptions: [:]
                )
            }
        )
        return projectDirectory
    }

    private func integrateWithXcodeProjectOrWorkspace(
        named projectHandle: String,
        in directory: AbsolutePath
    ) async throws -> String? {
        let integrateWithServer = prompter.promptIntegrateWithServer()
        if integrateWithServer {
            if try await serverSessionController.whoami(serverURL: Constants.URLs.production) == nil {
                try await ServiceContext.current?.ui?.collapsibleStep(
                    title: "Authentication",
                    successMessage: "Authenticated",
                    errorMessage: "Authentication failed",
                    visibleLines: 3,
                    task: { progress in

                        try await loginService.run(email: nil, password: nil, directory: nil) { event in
                            progress("\(event.description)")
                        }
                    }
                )
            }

            let accountHandle = try await serverSessionController.whoami(serverURL: Constants.URLs.production)!
            let fullHandle = "\(accountHandle)/\(projectHandle)"

            try await ServiceContext.current?.ui?.progressStep(
                message: "Creating Tuist project",
                successMessage: "Project created",
                errorMessage: "Project creation failed",
                showSpinner: true,
                task: { _ in
                    _ = try await createProjectService.createProject(fullHandle: fullHandle, serverURL: Constants.URLs.production)
                }
            )

            return fullHandle
        }

        return nil
    }

    private func nameOfXcodeProjectOrWorkspace(in directory: AbsolutePath) async throws -> StartPromptingWorkflowType {
        let xcodeProjectsAndWorkspaces = try await findXcodeProjectsAndWorkspaces(in: directory)
        return prompter
            .promptWorkflowType(
                xcodeProjectOrWorkspace: xcodeProjectsAndWorkspaces
                    .first(where: \.isWorkspace) ?? xcodeProjectsAndWorkspaces.first(where: \.isProject)
            )
    }

    private func findXcodeProjectsAndWorkspaces(in directory: AbsolutePath) async throws -> Set<XcodeProjectOrWorkspace> {
        var paths = Set(
            try await fileSystem.glob(directory: directory, include: ["**/*.xcworkspace"]).collect()
                .map(XcodeProjectOrWorkspace.workspace)
        )
        paths
            .formUnion(
                try await fileSystem.glob(directory: directory, include: ["**/*.xcodeproj"]).collect()
                    .map(XcodeProjectOrWorkspace.project)
            )
        paths
            .subtract(
                try await fileSystem.glob(directory: directory, include: ["**/*.xcodeproj/project.xcworkspace"]).collect()
                    .map(XcodeProjectOrWorkspace.workspace)
            )
        return paths
    }
}
