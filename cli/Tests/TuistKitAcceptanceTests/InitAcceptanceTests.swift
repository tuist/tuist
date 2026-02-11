import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistBuildCommand
import TuistGenerateCommand
import TuistSupport
import TuistTesting
@testable import TuistKit

struct InitAcceptanceTests {
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func generated_macos_app() async throws {
        let fileSystem = FileSystem()
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let initAnswers = InitPromptAnswers(
                workflowType: .createGeneratedProject,
                integrateWithServer: false,
                generatedProjectPlatform: "macos",
                generatedProjectName: "Test",
                accountType: .createOrganizationAccount,
                newOrganizationAccountHandle: "organization"
            )
            try await TuistTest.run(
                InitCommand.self,
                [
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString,
                ]
            )
            let fixturePath = temporaryDirectory.appending(component: "Test")
            try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
            try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixturePath.pathString])
            try await TuistTest.run(
                BuildCommand.self,
                ["--path", fixturePath.pathString, "--derived-data-path", derivedDataPath.pathString]
            )

            let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
            let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
            #expect(configFileCreated)
            #expect(miseFileCreated)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func generated_ios_app() async throws {
        let fileSystem = FileSystem()
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let initAnswers = InitPromptAnswers(
                workflowType: .createGeneratedProject,
                integrateWithServer: false,
                generatedProjectPlatform: "ios",
                generatedProjectName: "Test",
                accountType: .createOrganizationAccount,
                newOrganizationAccountHandle: "organization"
            )
            try await TuistTest.run(
                InitCommand.self,
                [
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString,
                ]
            )
            let fixturePath = temporaryDirectory.appending(component: "Test")
            try await TuistTest.run(InstallCommand.self, ["--path", fixturePath.pathString])
            try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixturePath.pathString])
            try await TuistTest.run(
                BuildCommand.self,
                ["--path", fixturePath.pathString, "--derived-data-path", derivedDataPath.pathString]
            )

            let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
            let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
            #expect(configFileCreated)
            #expect(miseFileCreated)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withFixture("xcode_project_ios_app"))
    func xcode_project_ios_app() async throws {
        let fileSystem = FileSystem()
        let fixturePath = try #require(TuistTest.fixtureDirectory)

        let initAnswers = InitPromptAnswers(
            workflowType: .connectProjectOrSwiftPackage("App"),
            integrateWithServer: false,
            generatedProjectPlatform: "",
            generatedProjectName: "",
            accountType: .createOrganizationAccount,
            newOrganizationAccountHandle: "organization"
        )

        try await TuistTest.run(
            InitCommand.self,
            [
                "--answers",
                initAnswers.base64EncodedJSONString(),
                "--path",
                fixturePath.pathString,
            ]
        )

        let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
        let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
        #expect(configFileCreated)
        #expect(miseFileCreated)
    }
}
