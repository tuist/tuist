import Basic
import Foundation
import TuistCore

/// Protocol that represents an entity that knows how to get the environment status
/// for a given graph and how to configure it.
protocol GraphUpping: AnyObject {
    /// It returns true if all the up commands from the graph projects are met.
    ///
    /// - Parameters
    ///   - graph: Project dependency graph.
    /// - Returns: True if all the up commands from the graph projects are met.
    /// - Throws: An error if the isMet of any of those commands throws.
    func isMet(graph: Graph) throws -> Bool

    /// It runs meet on each the commands of the graph projects if they are not met.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if any of the commands exit unsuccessfully.
    func meet(graph: Graph) throws
}

final class GraphUp: GraphUpping {
    /// Printer instance to output information to the user.
    fileprivate let printer: Printing

    /// System instance to run commands on the shell.
    fileprivate let system: Systeming

    /// Default initializer.
    ///
    /// - Parameters:
    ///   - printer: Printer instance to output information to the user.
    ///   - system: System instance to run commands on the shell.
    init(printer: Printing,
         system: Systeming) {
        self.printer = printer
        self.system = system
    }

    /// It runs meet on each the commands of the graph projects if they are not met.
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if any of the commands exit unsuccessfully.
    func meet(graph: Graph) throws {
        for project in graph.projects {
            printer.print(section: "Setting up environment for \(project.path)")
            for command in project.up {
                if try !command.isMet(system: system, projectPath: project.path) {
                    printer.print(subsection: "Configuring \(command.name)")
                    try command.meet(system: system, printer: printer, projectPath: project.path)
                }
            }
        }
    }

    /// It returns true if all the up commands from the graph projects are met.
    ///
    /// - Parameters
    ///   - graph: Project dependency graph.
    /// - Returns: True if all the up commands from the graph projects are met.
    /// - Throws: An error if the isMet of any of those commands throws.
    func isMet(graph: Graph) throws -> Bool {
        for project in graph.projects {
            for command in project.up {
                if try !command.isMet(system: system, projectPath: project.path) { return false }
            }
        }
        return true
    }
}
