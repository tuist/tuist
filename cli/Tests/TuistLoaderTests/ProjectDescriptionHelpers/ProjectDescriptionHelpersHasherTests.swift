import FileSystem
import FileSystemTesting
import Mockable
import ProjectDescription
import Testing
import TuistCore
import TuistEnvironment
import TuistSupport
@testable import TuistLoader
@testable import TuistTesting

struct ProjectDescriptionHelpersHasherTests {
    private var subject: ProjectDescriptionHelpersHasher!
    private var machineEnvironment: MockMachineEnvironmentRetrieving!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftlangVersion()
            .willReturn("5.7.0.127.4")
        let macOSSDKVersionProviderMock = try #require(MacOSSDKVersionProvider.mocked)
        given(macOSSDKVersionProviderMock)
            .macOSSDKVersion()
            .willReturn("26.5")
        machineEnvironment = .init()
        given(machineEnvironment)
            .macOSVersion
            .willReturn("15.2.4")
        subject = ProjectDescriptionHelpersHasher(
            tuistVersion: "3.2.1",
            machineEnvironment: machineEnvironment
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedMacOSSDKVersionProvider,
        .withMockedEnvironment(),
        .inTemporaryDirectory
    ) func hash() async throws {
        // Given
        let environmentMock = try #require(TuistEnvironment.Environment.mocked)
        let temporaryDir = try #require(FileSystem.temporaryTestDirectory)
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try await FileSystem().writeText("import ProjectDescription", at: helperPath)
        environmentMock.manifestLoadingVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        var firstHash: String?
        for _ in 0 ..< 20 {
            let got = try await subject.hash(helpersDirectory: temporaryDir)
            if let firstHash {
                #expect(got == firstHash)
            } else {
                firstHash = got
            }
        }
    }
}
