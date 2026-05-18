import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Rosalind
import Testing
import TuistConfigLoader
import TuistCore
import TuistGit
import TuistKit
import TuistServer
import TuistSupport
import TuistTesting
import TuistXcodeBuildProducts

@testable import TuistInspectCommand

struct InspectBundleCommandServiceTests {
    private let fileSystem = FileSystem()
    private let rosalind = MockRosalind()
    private let createBundleService = MockCreateBundleServicing()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()
    private let buildProductService = MockBuildProductServicing()
    private let appBundleTargetResolver = MockAppBundleTargetResolving()
    private let subject: InspectBundleCommandService

    init() {
        subject = InspectBundleCommandService(
            rosalind: rosalind,
            createBundleService: createBundleService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            fileSystem: fileSystem,
            buildProductService: buildProductService,
            appBundleTargetResolver: appBundleTargetResolver
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test(ref: "refs/pull/1/merge", branch: nil, sha: nil))

        given(serverEnvironmentService)
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
            .willReturn(.init(
                app_bundle_id: "dev.tuist",
                id: UUID().uuidString,
                inserted_at: Date(),
                install_size: 10,
                name: "App",
                supported_platforms: [],
                uploaded_by_account: "tuist",
                url: "https://tuist.dev/\(UUID().uuidString)",
                version: "1.0.0"
            ))

        given(rosalind)
            .analyzeAppBundle(at: .any)
            .willReturn(
                AppBundleReport(
                    bundleId: "dev.tuist",
                    name: "App",
                    type: .app,
                    installSize: 10,
                    downloadSize: 10,
                    platforms: [],
                    version: "1.0.0",
                    artifacts: []
                )
            )
    }

    @Test(.inTemporaryDirectory) func analyzeAppBundle() async throws {
        try await withMockedDependencies {
            // Given
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let bundlePath = temporaryDirectory.appending(component: "App.ipa")

            // When
            try await subject.run(
                path: temporaryDirectory.pathString,
                bundle: bundlePath.pathString,
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
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
                .gitInfo(workingDirectory: .value(temporaryDirectory))
                .called(1)
        }
    }

    @Test(.inTemporaryDirectory)
    func analyzeAppBundle_resolving_app_name_from_built_products() async throws {
        try await withMockedDependencies {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let bundlePath = temporaryDirectory.appending(component: "App.app")

            given(appBundleTargetResolver)
                .resolve(
                    app: .value("App"),
                    path: .value(temporaryDirectory),
                    configuration: .value("Debug"),
                    platforms: .value([.iOS]),
                    derivedDataPath: .value(nil)
                )
                .willReturn(ResolvedAppBundleTarget(
                    app: "App",
                    workspacePath: workspacePath,
                    configuration: "Debug",
                    platforms: [.iOS],
                    derivedDataPath: nil
                ))

            given(buildProductService)
                .appBundlePath(
                    app: .value("App"),
                    projectPath: .value(workspacePath),
                    derivedDataPath: .value(nil),
                    configuration: .value("Debug"),
                    platforms: .value([.iOS])
                )
                .willReturn(bundlePath)

            // When
            try await subject.run(
                path: temporaryDirectory.pathString,
                bundle: "App",
                configuration: "Debug",
                platforms: [.iOS],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(rosalind)
                .analyzeAppBundle(at: .value(bundlePath))
                .called(1)
        }
    }
}

@Mockable
protocol Rosalind: Rosalindable {
    func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport
}
