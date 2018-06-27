import Foundation

enum XpmEnvError: FatalError {
    case noVersionAvailable
    case pathNotFound(Version)

    var errorDescription: String {
        switch self {
        case .noVersionAvailable:
            return "Couldn't find any local xpm version available. Try running again."
        case let .pathNotFound(version):
            return "Couldn't get the local path for version \(version.description)"
        }
    }
}

do {
    let environmentController = LocalEnvironmentController()
    try environmentController.setup()
    let githubClient = GitHubClient()
    let localVersionsController = LocalVersionsController(environmentController: environmentController)
    let versionResolver = VersionResolver()
    let updatesController = UpdatesController(client: githubClient,
                                              localVersionsController: localVersionsController)
    let releaseDownloader = ReleseDownloader(localEnvironmentController: environmentController)

    let currentPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let currentDirectoryVersion = try versionResolver.resolve(path: currentPath)

    let shouldCheckForUpdates = (currentDirectoryVersion == nil) || !localVersionsController.versions().contains(currentDirectoryVersion!)

    /// Check and download new releases.
    if shouldCheckForUpdates, let release = try updatesController.check() {
        try releaseDownloader.download(release: release)
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

    let cliPath = path.appendingPathComponent("xpm")

    /// We drop the first element, which is the path to this executable.
    let exitStatus = Process.run(path: cliPath.path, arguments: Array(CommandLine.arguments.dropFirst()))
    exit(exitStatus)
} catch let error as FatalError {
    let message = """
    \("Error:".bold().red()) \(error.errorDescription)
    
    \("Try again and if the problem persists, open an issue on https://github.com/xcode-project-manager/support/issues/new/choose".yellow())
    """
    print(message)
    exit(1)
} catch {
    let message = """
    \("Unexpected error".bold().red())
        
    \("Try again and if the problem persists, open an issue on https://github.com/xcode-project-manager/support/issues/new/choose".yellow())
    """
    print(message)
    exit(1)
}
