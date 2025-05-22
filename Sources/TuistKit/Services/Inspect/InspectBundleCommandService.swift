import FileSystem
import Foundation
import Noora
import Path
import Rosalind
import TuistCLIServer
import TuistLoader
import TuistServer
import TuistSupport

enum InspectBundleCommandServiceError: LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            "To analyze the app bundle, run 'tuist init' to connect to the Tuist server."
        }
    }
}

struct InspectBundleCommandService {
    private let fileSystem: FileSysteming
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverURLService: ServerURLServicing
    private let gitController: GitControlling
    private let environment: [String: String]

    init(
        fileSystem: FileSysteming = FileSystem(),
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverURLService: ServerURLServicing = ServerURLService(),
        gitController: GitControlling = GitController(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileSystem = fileSystem
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverURLService = serverURLService
        self.gitController = gitController
        self.environment = environment
    }

    func run(
        path: String?,
        bundle: String,
        json: Bool
    ) async throws {
        let bundlePath = try AbsolutePath(
            validating: bundle,
            relativeTo: try await fileSystem.currentWorkingDirectory()
        )
        let path = try await self.path(path)

        let config = try await configLoader
            .loadConfig(path: path)

        if json {
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            let json = try appBundleReport.toJSON()
            Logger.current.info(
                .init(stringLiteral: json.toString(prettyPrint: true)),
                metadata: .json
            )
            return
        }

        guard let fullHandle = config.fullHandle else { throw InspectBundleCommandServiceError.missingFullHandle }

        let gitCommitSHA: String?
        let gitBranch: String?
        let gitRef = gitController.ref(environment: environment)
        if gitController.isInGitRepository(workingDirectory: path) {
            if gitController.hasCurrentBranchCommits(workingDirectory: path) {
                gitCommitSHA = try gitController.currentCommitSHA(workingDirectory: path)
            } else {
                gitCommitSHA = nil
            }

            gitBranch = try gitController.currentBranch(workingDirectory: path)
        } else {
            gitCommitSHA = nil
            gitBranch = nil
        }

        let serverURL = try serverURLService.url(configServerURL: config.url)
        let serverBundle = try await Noora.current.progressStep(
            message: "Analyzing bundle...",
            successMessage: "Bundle analyzed",
            errorMessage: nil,
            showSpinner: true
        ) { updateStep in
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            updateStep("Pushing bundle to the server...")
            return try await createBundleService.createBundle(
                fullHandle: fullHandle,
                serverURL: serverURL,
                appBundleReport: appBundleReport,
                gitCommitSHA: gitCommitSHA,
                gitBranch: gitBranch,
                gitRef: gitRef
            )
        }
        AlertController.current.success(.alert("View the bundle analysis at \(serverBundle.url.absoluteString)"))
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        if let path {
            return try await AbsolutePath(validating: path, relativeTo: fileSystem.currentWorkingDirectory())
        } else {
            return try await fileSystem.currentWorkingDirectory()
        }
    }
}
