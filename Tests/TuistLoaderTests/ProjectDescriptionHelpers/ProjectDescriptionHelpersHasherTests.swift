import FileSystem
import FileSystemTesting
import Mockable
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
@testable import TuistLoader
@testable import TuistTesting

struct ProjectDescriptionHelpersHasherTests {
    private var subject: ProjectDescriptionHelpersHasher!
    private var machineEnvironment: MockMachineEnvironmentRetrieving!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")
        machineEnvironment = .init()
        given(machineEnvironment)
            .macOSVersion
            .willReturn("15.2.4")
        subject = ProjectDescriptionHelpersHasher(
            tuistVersion: "3.2.1",
            machineEnvironment: machineEnvironment
        )
    }

    @Test(.withMockedSwiftVersionProvider, .withMockedEnvironment(), .inTemporaryDirectory) func hash() async throws {
        // Given
        let environmentMock = try #require(TuistSupport.Environment.mocked)
        let temporaryDir = try #require(FileSystem.temporaryTestDirectory)
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write("import ProjectDescription", path: helperPath, atomically: true)
        environmentMock.manifestLoadingVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        for _ in 0 ..< 20 {
            let got = try await subject.hash(helpersDirectory: temporaryDir)
            #expect(got == "5032b92c268cb7283c91ee37ec935c73")
        }
    }
}
