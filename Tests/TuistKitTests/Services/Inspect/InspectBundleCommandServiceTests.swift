import FileSystem
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
            gitController: gitController
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(createBundleService)
            .createBundle(
                fullHandle: .any,
                serverURL: .any,
                appBundleReport: .any,
                gitCommitSHA: .any,
                gitBranch: .any
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

    @Test func analyzeAppBundle() async throws {
        try await ServiceContext.withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
                // Given
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
                        gitBranch: .any
                    )
                    .called(1)
            }
        }
    }
}

@Mockable
protocol Rosalind: Rosalindable {
    func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport
}
