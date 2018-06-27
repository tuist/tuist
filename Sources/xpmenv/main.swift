import Foundation

enum XpmEnvError: Error, CustomStringConvertible {
    case noVersionAvailable
    case pathNotFound(Version)

    var description: String {
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

} catch {
    let stringConvertibleError = error as CustomStringConvertible
    let message = """
    An internal error happened: \(stringConvertibleError.description)
        
    Try again and if the problem persists, create an issue on https://github.com/xcode-project-manager/support
    """
    print(message)
    exit(1)
}
