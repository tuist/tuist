import Basic
import Foundation
import TuistCore

protocol CarthageControlling: AnyObject {
    func updateIfNecessary(graph: Graphing) throws
}

final class CarthageController: CarthageControlling {

    // MARK: - Static

    private static let pathRegex: NSRegularExpression = try! NSRegularExpression(pattern: "(.+)/Carthage/Build/.+/.+\\.framework", options: [])

    static func isCarthageFramework(_ path: AbsolutePath) -> Bool {
        let range = NSRange(location: 0, length: path.asString.count)
        if CarthageController.pathRegex.matches(in: path.asString, options: [], range: range).isEmpty {
            return false
        }
        return true
    }

    // MARK: - Attributes

    private let system: Systeming
    private let fileHandler: FileHandling
    private let printer: Printing

    // MARK: - Init

    init(system: Systeming = System(),
         fileHandler: FileHandling = FileHandler(),
         printer: Printing = Printer()) {
        self.system = system
        self.fileHandler = fileHandler
        self.printer = printer
    }

    // MARK: - CarthageControlling

    func updateIfNecessary(graph: Graphing) throws {
        let carthageDependencies = self.carthageDependencies(graph: graph)
        if carthageDependencies.isEmpty { return }

        let nonExistingCarthageDependencies = carthageDependencies.filter { !fileHandler.exists($0) }
        if nonExistingCarthageDependencies.isEmpty { return }

        printDependenciesToUpdate(paths: nonExistingCarthageDependencies)

        let foldersWithCartfile = self.foldersWithCartfile(dependenciesPaths: nonExistingCarthageDependencies)
        try updateDependencies(foldersWithCartfile: foldersWithCartfile)
    }

    // MARK: - Private

    private func updateDependencies(foldersWithCartfile: [AbsolutePath]) throws {
        guard let carthagePath = try self.carthagePath() else {
            throw CarthageError.notFound
        }

        try foldersWithCartfile.forEach { path in
            printer.print("Updating Carthage dependencies at \(path.asString)")

            try system.capture(carthagePath.asString,
                               "--project-directory",
                               path.asString, verbose: true).throwIfError()
        }
    }

    private func printDependenciesToUpdate(paths: [AbsolutePath]) {
        var message = "The following Carthage dependencies need to be pulled:\n"
        message.append(paths.map({ " - \($0.asString)" }).joined(separator: "\n"))
        printer.print(message)
    }

    private func carthagePath() throws -> AbsolutePath? {
        do {
            guard let path = try system.capture("which", "carthage", verbose: false).stdout.chuzzle() else {
                return nil
            }
            return AbsolutePath(path)
        } catch {
            return nil
        }
    }

    func foldersWithCartfile(dependenciesPaths: [AbsolutePath]) -> [AbsolutePath] {
        return dependenciesPaths.compactMap { (path) -> AbsolutePath? in
            let pathString = path.asString
            let pathRange = NSRange(location: 0, length: pathString.count)

            guard let match = CarthageController.pathRegex.firstMatch(in: pathString, options: [], range: pathRange) else {
                return nil
            }

            let folderPath = AbsolutePath((pathString as NSString).substring(with: match.range(at: 1)))
            let cartfilePath = folderPath.appending(component: "Cartfile")

            if fileHandler.exists(cartfilePath) {
                return folderPath
            }

            return nil
        }
    }

    func carthageDependencies(graph: Graphing) -> [AbsolutePath] {
        let precompiledPaths = graph.precompiledNodes.map { $0.path }
        return precompiledPaths.compactMap { (path) -> AbsolutePath? in
            let pathString = path.asString
            let pathRange = NSRange(location: 0, length: pathString.count)
            if CarthageController.pathRegex.matches(in: pathString, options: [], range: pathRange).isEmpty {
                return nil
            }
            return path
        }
    }
}
