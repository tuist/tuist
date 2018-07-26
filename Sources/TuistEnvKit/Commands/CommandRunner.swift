import Foundation
import TuistCore
import Basic

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
            return "No valid version has been found locally."
        }
    }
}

class CommandRunner: CommandRunning {

    // MARK: - Attributes
    
    let versionResolver: VersionResolving
    let fileHandler: FileHandling
    let printer: Printing
    let commandRunnerMessageMapper: CommandRunnerMessageMapping
    let system: Systeming
    let updater: Updating
    let versionsController: VersionsControlling
    let installer: Installing
    let arguments: () -> [String]
    let exiter: (Int) -> ()
    
    // MARK: - Init
    
    init(versionResolver: VersionResolving = VersionResolver(),
         fileHandler: FileHandling = FileHandler(),
         printer: Printing = Printer(),
         commandRunnerMessageMapper: CommandRunnerMessageMapping = CommandRunnerMessageMapper(),
         system: Systeming = System(),
         updater: Updating = Updater(),
         installer: Installing = Installer(),
         versionsController: VersionsControlling = VersionsController(),
         arguments: @escaping () -> [String] = CommandRunner.arguments,
         exiter: @escaping (Int) -> () = { exit(Int32($0)) }) {
        self.versionResolver = versionResolver
        self.fileHandler = fileHandler
        self.printer = printer
        self.commandRunnerMessageMapper = commandRunnerMessageMapper
        self.system = system
        self.versionsController = versionsController
        self.arguments = arguments
        self.updater = updater
        self.installer = installer
        self.exiter = exiter
    }

    // MARK: - CommandRunning
    
    func run() throws {
        let currentPath = fileHandler.currentPath

        // Version resolving
        let resolvedVersion = try versionResolver.resolve(path: currentPath)
        if let resolvedVersionMessage = commandRunnerMessageMapper.resolvedVersion(resolvedVersion) {
            printer.print(resolvedVersionMessage)
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
            try updater.update()
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
            printer.print("Version \(version) not found locally. Installing...")
            try installer.install(version: version)
        }
        
        if !versionsController.versions().contains(where: {$0.description == version}) {
            throw CommandRunnerError.versionNotFound
        }

        let path = versionsController.path(version: version)
        try runAtPath(path)
    }
    
    func runAtPath(_ path: AbsolutePath) throws {
        var args = [path.appending(component: Constants.binName).asString]
        args.append(contentsOf: Array(arguments().dropFirst()))
        
        try system.popen(args,
                     printing: true,
                     verbose: false,
                     onOutput: nil,
                     onError: nil) { self.exiter($0) }
    }
    
    // MARK: - Static
    
    static func arguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }
}
