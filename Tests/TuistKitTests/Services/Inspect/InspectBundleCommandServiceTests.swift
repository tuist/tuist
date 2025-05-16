import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Rosalind
import ServiceContextModule
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

struct InspectBundleCommandServiceTests {
    private let fileSystem = FileSystem()
    private let rosalind = MockRosalind()
    private let createBundleService = MockCreateBundleServicing()
    private let configLoader = MockConfigLoading()
    private let serverURLService = MockServerURLServicing()
    private let gitController = MockGitControlling()
    private let subject: InspectBundleCommandService

    init() {
        subject = InspectBundleCommandService(
            fileSystem: fileSystem,
            rosalind: rosalind,
            createBundleService: createBundleService,
            configLoader: configLoader,
            serverURLService: serverURLService,
            gitController: gitController,
            environment: [:]
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .ref(environment: .any)
            .willReturn("refs/pull/1/merge")

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(createBundleService)
            .createBundle(
                fullHandle: .any,
                serverURL: .any,
                appBundleReport: .any,
                gitCommitSHA: .any,
                gitBranch: .any,
                gitRef: .any
            )
            .willReturn(.test())

        given(rosalind)
            .analyzeAppBundle(at: .any)
            .willReturn(
                AppBundleReport(
                    bundleId: "com.tuist",
                    name: "App",
                    installSize: 10,
                    downloadSize: 10,
                    platforms: [],
                    version: "1.0.0",
                    artifacts: []
                )
            )
    }

    @Test(.inTemporaryDirectory) func analyzeAppBundle() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let bundlePath = temporaryDirectory.appending(component: "App.ipa")

            // When
            try await subject.run(
                path: temporaryDirectory.pathString,
                bundle: bundlePath.pathString,
                json: false
            )

            // Then
            verify(createBundleService)
                .createBundle(
                    fullHandle: .any,
                    serverURL: .any,
                    appBundleReport: .any,
                    gitCommitSHA: .any,
                    gitBranch: .any,
                    gitRef: .value("refs/pull/1/merge")
                )
                .called(1)

            verify(gitController)
                .isInGitRepository(workingDirectory: .value(temporaryDirectory))
                .called(1)
        }
    }
}

@Mockable
protocol Rosalind: Rosalindable {
    func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport
}
