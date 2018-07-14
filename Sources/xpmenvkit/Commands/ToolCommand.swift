import Basic
import Foundation
import Utility

enum XpmEnvError: FatalError {
    case noVersionAvailable
    case pathNotFound(Version)

    var errorDescription: String {
        switch self {
        case .noVersionAvailable:
            return "Couldn't find any local xpm version available."
        case let .pathNotFound(version):
            return "Couldn't get the local path for version \(version.description)."
        }
    }
}

public class XPMEnvCommand {
    public init() {}

    public func execute() {
        do {
            let environmentController = EnvironmentController()
            try environmentController.setup()
            let githubClient = GitHubClient()
            let localVersionsController = LocalVersionsController(environmentController: environmentController)
            let versionResolver = VersionResolver()
            let updatesController = UpdatesController(client: githubClient,
                                                      localVersionsController: localVersionsController)
//            let releaseDownloader = ReleaseDownloader(EnvironmentController: environmentController)

            let currentPath = AbsolutePath(FileManager.default.currentDirectoryPath)
            let currentDirectoryVersion = try versionResolver.resolve(path: currentPath)

            let shouldCheckForUpdates = (currentDirectoryVersion == nil) || !localVersionsController.versions().contains(currentDirectoryVersion!)

            /// Check and download new releases.
            if shouldCheckForUpdates, let release = try updatesController.check() {
//                try releaseDownloader.download(release: release)
            }

            /// Determine the version that we should open
            var versionToOpen: Version!
            if let currentDirectoryVersion = currentDirectoryVersion {
                versionToOpen = currentDirectoryVersion
            } else {
                versionToOpen = localVersionsController.versions().sorted().last
            }

            if versionToOpen == nil {
                throw XpmEnvError.noVersionAvailable
            }

            guard let path = localVersionsController.path(version: versionToOpen) else {
                throw XpmEnvError.pathNotFound(versionToOpen)
            }

            let cliPath = path.appending(component: "xpm")

            var arguments: [String] = [cliPath.asString]
            /// We drop the first element, which is the path to this executable.
            arguments.append(contentsOf: Array(CommandLine.arguments.dropFirst()))
            let status: ProcessResult.ExitStatus = try Process.popen(arguments: arguments).exitStatus
            if case let ProcessResult.ExitStatus.signalled(code) = status {
                exit(code)
            } else if case let ProcessResult.ExitStatus.terminated(code) = status {
                exit(code)
            } else {
                exit(0)
            }
        } catch let error as FatalError {
            let message = """
            \("Error:") \(error.errorDescription)
            
            \("Try again, and if the problem persists, open an issue on https://github.com/xcode-project-manager/support/issues/new")
            """
            print(message)
            exit(1)
        } catch {
            let message = """
            \("Unexpected error")
            
            \("Try again, and if the problem persists, open an issue on https://github.com/xcode-project-manager/support/issues/new")
            """
            print(message)
            exit(1)
        }
    }
}
