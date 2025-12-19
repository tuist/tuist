import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XcodeProj
import XCTest
@testable import TuistKit

final class InitAcceptanceTestmacOSApp: TuistAcceptanceTestCase {
    func test_generated_macos_app() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                let initAnswers = InitPromptAnswers(
                    workflowType: .createGeneratedProject,
                    integrateWithServer: false,
                    generatedProjectPlatform: "macos",
                    generatedProjectName: "Test",
                    accountType: .createOrganizationAccount,
                    newOrganizationAccountHandle: "organization"
                )
                try await run(
                    InitCommand.self,
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString
                )
                self.fixturePath = temporaryDirectory.appending(component: "Test")
                try await run(InstallCommand.self)
                try await run(GenerateCommand.self)
                try await run(BuildCommand.self)

                let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
                let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
                XCTAssertTrue(configFileCreated)
                XCTAssertTrue(miseFileCreated)
            }
        }
    }

    func test_generated_ios_app() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                let initAnswers = InitPromptAnswers(
                    workflowType: .createGeneratedProject,
                    integrateWithServer: false,
                    generatedProjectPlatform: "ios",
                    generatedProjectName: "Test",
                    accountType: .createOrganizationAccount,
                    newOrganizationAccountHandle: "organization"
                )
                try await run(
                    InitCommand.self,
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    temporaryDirectory.pathString
                )
                self.fixturePath = temporaryDirectory.appending(component: "Test")
                try await run(InstallCommand.self)
                try await run(GenerateCommand.self)
                try await run(BuildCommand.self)

                let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
                let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
                XCTAssertTrue(configFileCreated)
                XCTAssertTrue(miseFileCreated)
            }
        }
    }

    func test_xcode_project_ios_app() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { _ in
                try await setUpFixture("xcode_project_ios_app")

                let initAnswers = InitPromptAnswers(
                    workflowType: .connectProjectOrSwiftPackage("App"),
                    integrateWithServer: false,
                    generatedProjectPlatform: "",
                    generatedProjectName: "",
                    accountType: .createOrganizationAccount,
                    newOrganizationAccountHandle: "organization"
                )

                try await run(
                    InitCommand.self,
                    "--answers",
                    initAnswers.base64EncodedJSONString(),
                    "--path",
                    fixturePath.pathString
                )

                let configFileCreated = try await fileSystem.exists(fixturePath.appending(component: "Tuist.swift"))
                let miseFileCreated = try await fileSystem.exists(fixturePath.appending(component: "mise.toml"))
                XCTAssertTrue(configFileCreated)
                XCTAssertTrue(miseFileCreated)
            }
        }
    }
}
