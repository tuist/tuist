import Foundation
import TuistCore

protocol GraphUpping: AnyObject {
    
    /// It returns true if all the up commands from the graph projects are met.
    ///
    /// - Parameter graph: Project dependency graph.
    /// - Returns: True if all the up commands from the graph projects are met.
    /// - Throws: An error if the isMet of any of those commands throws.
    func isMet(graph: Graph) throws -> Bool
    
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
    
    func meet(graph: Graph) throws {
        // TODO
    }
    
    /// It returns true if all the up commands from the graph projects are met.
    ///
    /// - Parameter graph: Project dependency graph.
    /// - Returns: True if all the up commands from the graph projects are met.
    /// - Throws: An error if the isMet of any of those commands throws.
    func isMet(graph: Graph) throws -> Bool {
        for project in graph.projects {
            for command in project.up {
                if try !command.isMet(system: system) { return false }
            }
        }
        return true
    }
    
}


