import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleShowServicing {
    func run(
        bundleId: String,
        directory: String?
    ) async throws
}

final class BundleShowService: BundleShowServicing {
    private let getBundleService: GetBundleServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getBundleService: GetBundleServicing = GetBundleService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getBundleService = getBundleService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        bundleId: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let bundle = try await getBundleService.getBundle(
            serverURL: serverURL,
            fullHandle: config.fullHandle,
            bundleId: bundleId
        )

        let json = bundle.toJSON()
        Logger.current.info(
            .init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json
        )
    }
}