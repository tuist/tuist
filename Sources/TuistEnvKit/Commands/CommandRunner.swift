import Basic
import Foundation
import TuistCore

protocol CommandRunning: AnyObject {
    func run() throws
}

enum CommandRunnerError: FatalError {
    case versionNotFound

    var type: ErrorType {
        switch self {
        case .versionNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .versionNotFound:
            return "No valid version has been found locally"
        }
    }
}

class CommandRunner: CommandRunning {
    // MARK: - Attributes

    let versionResolver: VersionResolving
    let environment: Environmenting
    let updater: Updating
    let versionsController: VersionsControlling
    let installer: Installing
    let arguments: () -> [String]
    let exiter: (Int) -> Void

    // MARK: - Init

    init(versionResolver: VersionResolving = VersionResolver(),
         environment: Environmenting = Environment.shared,
         updater: Updating = Updater(),
         installer: Installing = Installer(),
         versionsController: VersionsControlling = VersionsController(),
         arguments: @escaping () -> [String] = CommandRunner.arguments,
         exiter: @escaping (Int) -> Void = { exit(Int32($0)) }) {
        self.versionResolver = versionResolver
        self.environment = environment
        self.versionsController = versionsController
        self.arguments = arguments
        self.updater = updater
        self.installer = installer
        self.exiter = exiter
    }

    // MARK: - CommandRunning

    func run() throws {
        let currentPath = FileHandler.shared.currentPath

        // Version resolving
        let resolvedVersion = try versionResolver.resolve(path: currentPath)

        switch resolvedVersion {
        case let .bin(path):
            Printer.shared.print("Using bundled version at path \(path.pathString)")
        case let .versionFile(path, value):
            Printer.shared.print("Using version \(value) defined at \(path.pathString)")
        default:
            break
        }

        if case let ResolvedVersion.bin(path) = resolvedVersion {
            try runAtPath(path)
        } else if case let ResolvedVersion.versionFile(_, version) = resolvedVersion {
            try runVersion(version)
        } else {
            try runHighestLocalVersion()
        }
    }

    // MARK: - Fileprivate

    func runHighestLocalVersion() throws {
        var version: String!

        if let highgestVersion = versionsController.semverVersions().last?.description {
            version = highgestVersion
        } else {
            try updater.update(force: false)
            guard let highgestVersion = versionsController.semverVersions().last?.description else {
                throw CommandRunnerError.versionNotFound
            }
            version = highgestVersion
        }

        let path = versionsController.path(version: version)
        try runAtPath(path)
    }

    func runVersion(_ version: String) throws {
        if !versionsController.versions().contains(where: { $0.description == version }) {
            Printer.shared.print("Version \(version) not found locally. Installing...")
            try installer.install(version: version, force: false)
        }

        let path = versionsController.path(version: version)
        try runAtPath(path)
    }

    func runAtPath(_ path: AbsolutePath) throws {
        var args = [path.appending(component: Constants.binName).pathString]
        args.append(contentsOf: Array(arguments().dropFirst()))

        var environment = ProcessInfo.processInfo.environment
        environment[Constants.EnvironmentVariables.colouredOutput] = "\(self.environment.shouldOutputBeColoured)"

        do {
            try System.shared.runAndPrint(args, verbose: false, environment: environment)
        } catch {
            exiter(1)
        }
    }

    // MARK: - Static

    static func arguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }
}
