import Foundation
import Path
import TuistAutomation
import TuistSupport
import TuistCore
import TuistServer
import TuistLoader
import XcodeGraph

struct ShareService {
    private let fileHandler: FileHandling
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let buildGraphInspector: BuildGraphInspecting
    private let buildsUploadService: BuildsUploadServicing
    private let configLoader: ConfigLoading
    private let cloudURLService: CloudURLServicing
    
    init() {
        self.init(
            fileHandler: FileHandler.shared,
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
            buildGraphInspector: BuildGraphInspector(),
            buildsUploadService: BuildsUploadService(),
            configLoader: ConfigLoader(),
            cloudURLService: CloudURLService()
        )
    }
    
    init(
        fileHandler: FileHandling,
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
        buildGraphInspector: BuildGraphInspecting,
        buildsUploadService: BuildsUploadServicing,
        configLoader: ConfigLoading,
        cloudURLService: CloudURLServicing
    ) {
        self.fileHandler = fileHandler
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.buildGraphInspector = buildGraphInspector
        self.buildsUploadService = buildsUploadService
        self.configLoader = configLoader
        self.cloudURLService = cloudURLService
    }
    
    func run(
        path: String?,
        configuration: String?
    ) async throws {
        let path = try self.path(path)
        
        guard let workspacePath = try buildGraphInspector.workspacePath(directory: path) else {
            // TODO: Change error
            throw RunServiceError.workspaceNotFound(path: path.pathString)
        }

        let configuration = configuration /* TODO: Only when Tuist project is present?? target.project.settings.defaultDebugBuildConfiguration()?.name */?? BuildConfiguration
                    .debug.name
        let xcodeBuildDirectory = try xcodeProjectBuildDirectoryLocator.locate(
            platform: .iOS, /* TODO: Make this configurable */
            projectPath: workspacePath,
            derivedDataPath: nil,
            configuration: configuration
        )
        
        let config = try configLoader.loadConfig(path: path)
        let serverURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
        
        // TODO: Make the product name configurable
        let appPath = xcodeBuildDirectory.appending(component: "App.app")
        try await buildsUploadService.uploadBuild(appPath, serverURL: serverURL)
    }
    
    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
