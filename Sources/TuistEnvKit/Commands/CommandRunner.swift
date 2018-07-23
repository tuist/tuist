import Foundation
import TuistCore

protocol CommandRunning: AnyObject {
    func run() throws
}

class CommandRunner: CommandRunning {
    /// Version resolver.
    let versionResolver: VersionResolving

    /// File handler.
    let fileHandler: FileHandling

    /// Printer.
    let printer: Printing

    /// Resolved version message mapper.
    let commandRunnerMessageMapper: CommandRunnerMessageMapping

    init(versionResolver: VersionResolving = VersionResolver(),
         fileHandler: FileHandling = FileHandler(),
         printer: Printing = Printer(),
         commandRunnerMessageMapper: CommandRunnerMessageMapping = CommandRunnerMessageMapper()) {
        self.versionResolver = versionResolver
        self.fileHandler = fileHandler
        self.printer = printer
        self.commandRunnerMessageMapper = commandRunnerMessageMapper
    }

    func run() throws {
        let currentPath = fileHandler.currentPath

        // Version resolving
        let resolvedVersion = try versionResolver.resolve(path: currentPath)
        if let resolvedVersionMessage = commandRunnerMessageMapper.resolvedVersion(resolvedVersion) {
            printer.print(resolvedVersionMessage)
        }
    }
}
