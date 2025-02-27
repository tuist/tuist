import FileSystem
import Foundation
import Mockable
import Noora
import ServiceContextModule
import Testing
import TuistServer
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

private struct MockKeyStrokeListening: KeyStrokeListening {
    var stubbedKeyStrokes: [KeyStroke] = []

    func listen(terminal _: any Terminaling, onKeyPress: @escaping (KeyStroke) -> OnKeyPressResult) {
        for keyStroke in stubbedKeyStrokes {
            _ = onKeyPress(keyStroke)
        }
    }
}

struct InitServiceTests {
    private let fileSystem = FileSystem()
    private let prompter = MockStartPrompting()
    private let loginService = MockLoginServicing()
    private let createProjectService = MockCreateProjectServicing()
    private let serverSessionController = MockServerSessionControlling()
    private let startGeneratedProjectService = InitGeneratedProjectService()
    private let keystrokeListener = MockKeyStrokeListening()
    private let subject: InitService

    init() {
        subject = InitService(
            fileSystem: fileSystem,
            prompter: prompter,
            loginService: loginService,
            createProjectService: createProjectService,
            serverSessionController: serverSessionController,
            startGeneratedProjectService: startGeneratedProjectService,
            keystrokeListener: keystrokeListener
        )
    }

    @Test func generatesTheRightConfiguration_when_generatedAndConnectedToServer() async throws {
        try await ServiceContext.withTestingDependencies {
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any).willReturn(.createGeneratedProject)
            given(prompter).promptGeneratedProjectName().willReturn("Test")
            given(prompter).promptIntegrateWithServer().willReturn(true)
            given(prompter).promptGeneratedProjectPlatform().willReturn("ios")
            given(loginService).run(email: .value(nil), password: .value(nil), directory: .any, onEvent: .any).willReturn()
            given(serverSessionController).whoami(serverURL: .value(Constants.URLs.production)).willReturn("account")
            given(createProjectService).createProject(
                fullHandle: .value("account/Test"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "account/Test"))

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // When
                try await subject.run(from: temporaryDirectory)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(at: temporaryDirectory.appending(components: [
                    "Test",
                    "Tuist.swift",
                ]))
                #expect(tuistSwift == """
                import ProjectDescription

                let tuist = Tuist(fullHandle: "account/Test", project: .tuist())
                """)
            }
        }
    }

    @Test func generatesTheRightConfiguration_when_generatedAndNotConnectedToServer() async throws {
        try await ServiceContext.withTestingDependencies {
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any).willReturn(.createGeneratedProject)
            given(prompter).promptGeneratedProjectName().willReturn("Test")
            given(prompter).promptIntegrateWithServer().willReturn(false)
            given(prompter).promptGeneratedProjectPlatform().willReturn("ios")

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // When
                try await subject.run(from: temporaryDirectory)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(at: temporaryDirectory.appending(components: [
                    "Test",
                    "Tuist.swift",
                ]))
                #expect(tuistSwift == """
                import ProjectDescription

                let tuist = Tuist(project: .tuist())
                """)
            }
        }
    }

    @Test func generatesTheRightConfiguration_when_integrationWithExistingXcodeProjectAndConnectedToServer() async throws {
        try await ServiceContext.withTestingDependencies {
            let projectName = UUID().uuidString
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any)
                .willReturn(.integrateWithProjectOrWorkspace(projectName))
            given(prompter).promptIntegrateWithServer().willReturn(true)
            given(loginService).run(email: .value(nil), password: .value(nil), directory: .any, onEvent: .any).willReturn()
            given(serverSessionController).whoami(serverURL: .value(Constants.URLs.production)).willReturn("account")
            given(createProjectService).createProject(
                fullHandle: .value("account/\(projectName)"),
                serverURL: .value(Constants.URLs.production)
            ).willReturn(.test(fullName: "account/\(projectName)"))

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given

                try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "\(projectName).xcodeproj"))

                // When
                try await subject.run(from: temporaryDirectory)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(at: temporaryDirectory.appending(components: ["Tuist.swift"]))
                #expect(tuistSwift == """
                import ProjectDescription

                let tuist = Tuist(fullHandle: "account/\(projectName)", project: .xcode())
                """)
            }
        }
    }

    @Test func generatesTheRightConfiguration_when_integrationWithExistingXcodeProjectAndNotConnectedToServer() async throws {
        try await ServiceContext.withTestingDependencies {
            let projectName = UUID().uuidString
            given(prompter).promptWorkflowType(xcodeProjectOrWorkspace: .any)
                .willReturn(.integrateWithProjectOrWorkspace(projectName))
            given(prompter).promptIntegrateWithServer().willReturn(false)

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given

                try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "\(projectName).xcodeproj"))

                // When
                try await subject.run(from: temporaryDirectory)

                // Then
                let tuistSwift = try await fileSystem.readTextFile(at: temporaryDirectory.appending(components: ["Tuist.swift"]))
                #expect(tuistSwift == """
                import ProjectDescription

                let tuist = Tuist(project: .xcode())
                """)
            }
        }
    }
}
