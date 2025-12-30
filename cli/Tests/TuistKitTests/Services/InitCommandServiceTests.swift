import Command
import FileSystem
import Foundation
import Mockable
import Noora
import Testing
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

private struct MockKeyStrokeListening: KeyStrokeListening {
    var stubbedKeyStrokes: [KeyStroke] = []

    func listen(terminal _: any Terminaling, onKeyPress: @escaping (KeyStroke) -> OnKeyPressResult) {
        for keyStroke in stubbedKeyStrokes {
            _ = onKeyPress(keyStroke)
        }
    }
}

struct InitCommandServiceTests {
    private let fileSystem = FileSystem()
    private let prompter = MockInitPrompting()
    private let loginService = MockLoginServicing()
    private let createProjectService = MockCreateProjectServicing()
    private let serverSessionController = MockServerSessionControlling()
    private let startGeneratedProjectService = InitGeneratedProjectService()
    private let keystrokeListener = MockKeyStrokeListening()
    private let createOrganizationService = MockCreateOrganizationServicing()
    private let listOrganizationsService = MockListOrganizationsServicing()
    private let getProjectService = MockGetProjectServicing()
    private let commandRunner = MockCommandRunning()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let subject: InitCommandService

    init() {
        subject = InitCommandService(
            fileSystem: fileSystem,
            prompter: prompter,
            loginService: loginService,
            createProjectService: createProjectService,
            serverSessionController: serverSessionController,
            initGeneratedProjectService: startGeneratedProjectService,
            keystrokeListener: keystrokeListener,
            createOrganizationService: createOrganizationService,
            listOrganizationsService: listOrganizationsService,
            getProjectService: getProjectService,
            commandRunner: commandRunner,
            serverEnvironmentService: serverEnvironmentService
        )

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)
    }

    @Test func generatesTheRightConfiguration_when_generatedAndConnectedToServer() async throws {
        try await withMockedDependencies {
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any).willReturn(
                .createGeneratedProject
            )
            given(prompter).promptGeneratedProjectName().willReturn("Test")
            given(prompter).promptIntegrateWithServer().willReturn(true)
            given(prompter).promptGeneratedProjectPlatform().willReturn("ios")
            given(prompter).promptAccountType(
                authenticatedUserHandle: .value("account"), organizations: .value(["org"])
            )
            .willReturn(.createOrganizationAccount)
            given(prompter).promptNewOrganizationAccountHandle().willReturn("organization")
            given(createOrganizationService).createOrganization(
                name: .value("organization"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test())
            given(loginService).run(
                email: .value(nil), password: .value(nil), directory: .any, onEvent: .any
            ).willReturn()
            given(serverSessionController).whoami(serverURL: .value(Constants.URLs.production))
                .willReturn("account")
            given(getProjectService).getProject(
                fullHandle: .value("organization/Test"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "organization/Test"))
            given(createProjectService).createProject(
                fullHandle: .value("organization/Test"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "organization/Test"))
            given(listOrganizationsService).listOrganizations(
                serverURL: .value(Constants.URLs.production)
            ).willReturn(["org"])

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                given(commandRunner).run(
                    arguments: .matching { $0.contains("mise") }, environment: .any,
                    workingDirectory: .any
                )
                .willReturn(.init(unfolding: { nil }))

                // When
                try await subject.run(from: temporaryDirectory, answers: nil)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(
                    at: temporaryDirectory.appending(components: [
                        "Test",
                        "Tuist.swift",
                    ])
                )
                #expect(
                    tuistSwift == """
                    import ProjectDescription

                    let tuist = Tuist(fullHandle: "organization/Test", project: .tuist())
                    """
                )
            }
        }
    }

    @Test func generatesTheRightConfiguration_when_generatedAndNotConnectedToServer() async throws {
        try await withMockedDependencies {
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any).willReturn(
                .createGeneratedProject
            )
            given(prompter).promptGeneratedProjectName().willReturn("Test")
            given(prompter).promptIntegrateWithServer().willReturn(false)
            given(prompter).promptGeneratedProjectPlatform().willReturn("ios")

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                given(commandRunner).run(
                    arguments: .matching { $0.contains("mise") }, environment: .any,
                    workingDirectory: .any
                )
                .willReturn(.init(unfolding: { nil }))

                // When
                try await subject.run(from: temporaryDirectory, answers: nil)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(
                    at: temporaryDirectory.appending(components: [
                        "Test",
                        "Tuist.swift",
                    ])
                )
                #expect(
                    tuistSwift == """
                    import ProjectDescription

                    let tuist = Tuist(project: .tuist())
                    """
                )
            }
        }
    }

    @Test
    func
        generatesTheRightConfiguration_when_connectingAnExistingXcodeProject_and_connectedToServer()
        async throws
    {
        try await withMockedDependencies {
            let projectName = UUID().uuidString
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any)
                .willReturn(.connectProjectOrSwiftPackage(projectName))
            given(prompter).promptIntegrateWithServer().willReturn(true)
            given(prompter).promptAccountType(
                authenticatedUserHandle: .value("account"), organizations: .value(["org"])
            )
            .willReturn(.userAccount("account"))
            given(loginService).run(
                email: .value(nil), password: .value(nil), directory: .any, onEvent: .any
            ).willReturn()
            given(serverSessionController).whoami(serverURL: .value(Constants.URLs.production))
                .willReturn("account")
            given(getProjectService).getProject(
                fullHandle: .value("account/\(projectName)"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "account/\(projectName)"))
            given(createProjectService).createProject(
                fullHandle: .value("account/\(projectName)"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "account/\(projectName)"))
            given(listOrganizationsService).listOrganizations(
                serverURL: .value(Constants.URLs.production)
            ).willReturn(["org"])

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                given(commandRunner).run(
                    arguments: .matching { $0.contains("mise") }, environment: .any,
                    workingDirectory: .any
                )
                .willReturn(.init(unfolding: { nil }))
                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(component: "\(projectName).xcodeproj")
                )

                // When
                try await subject.run(from: temporaryDirectory, answers: nil)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(
                    at: temporaryDirectory.appending(components: ["Tuist.swift"])
                )
                #expect(
                    tuistSwift == """
                    import ProjectDescription

                    let tuist = Tuist(fullHandle: "account/\(projectName)", project: .xcode())
                    """
                )
            }
        }
    }

    @Test
    func
        generatesTheRightConfiguration_when_connectingAnExistingXcodeProject_and_NotConnectedToServer()
        async throws
    {
        try await withMockedDependencies {
            let projectName = UUID().uuidString
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any)
                .willReturn(.connectProjectOrSwiftPackage(projectName))
            given(prompter).promptIntegrateWithServer().willReturn(false)

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                // Given
                given(commandRunner).run(
                    arguments: .matching { $0.contains("mise") }, environment: .any,
                    workingDirectory: .any
                )
                .willReturn(.init(unfolding: { nil }))
                try await fileSystem.makeDirectory(
                    at: temporaryDirectory.appending(component: "\(projectName).xcodeproj")
                )

                // When
                try await subject.run(from: temporaryDirectory, answers: nil)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(
                    at: temporaryDirectory.appending(components: ["Tuist.swift"])
                )
                #expect(
                    tuistSwift == """
                    import ProjectDescription

                    let tuist = Tuist(project: .xcode())
                    """
                )
            }
        }
    }

    @Test func generatesTheRightConfiguration_whenGeneratedForOrganization_andConnectedToServer()
        async throws
    {
        try await withMockedDependencies {
            let organizationName = UUID().uuidString
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any).willReturn(
                .createGeneratedProject
            )
            given(prompter).promptGeneratedProjectName().willReturn("Test")
            given(prompter).promptIntegrateWithServer().willReturn(true)
            given(prompter).promptGeneratedProjectPlatform().willReturn("ios")
            given(prompter).promptAccountType(
                authenticatedUserHandle: .value("account"),
                organizations: .value([organizationName])
            ).willReturn(.organization(organizationName))
            given(loginService).run(
                email: .value(nil), password: .value(nil), directory: .any, onEvent: .any
            ).willReturn()
            given(serverSessionController).whoami(serverURL: .value(Constants.URLs.production))
                .willReturn("account")
            given(getProjectService).getProject(
                fullHandle: .value("\(organizationName)/Test"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "\(organizationName)/Test"))
            given(createProjectService).createProject(
                fullHandle: .value("\(organizationName)/Test"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "\(organizationName)/Test"))
            given(listOrganizationsService).listOrganizations(
                serverURL: .value(Constants.URLs.production)
            ).willReturn([organizationName])

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
                temporaryDirectory in
                given(commandRunner).run(
                    arguments: .matching { $0.contains("mise") }, environment: .any,
                    workingDirectory: .any
                )
                .willReturn(.init(unfolding: { nil }))

                // When
                try await subject.run(from: temporaryDirectory, answers: nil)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(
                    at: temporaryDirectory.appending(components: [
                        "Test",
                        "Tuist.swift",
                    ])
                )
                #expect(
                    tuistSwift == """
                    import ProjectDescription

                    let tuist = Tuist(fullHandle: "\(organizationName)/Test", project: .tuist())
                    """
                )
            }
        }
    }
}
