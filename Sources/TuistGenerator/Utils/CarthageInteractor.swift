import Foundation
import TuistCore

enum CarthageInteractorError: FatalError, Equatable {
    case carthageNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found"
        }
    }
}

protocol CarthageInteracting {
    /// Runs 'carthage checkout' to fetch all of the project dependencies
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the checkout fails.
    func checkout(graph: Graphing) throws
}

final class CarthageInteractor: CarthageInteracting {
    
    func checkout(graph: Graphing) throws {
        
        guard !graph.carthageDependencies.isEmpty else {
            return
        }
        
        let carthage = try System.shared.which(
            "carthage",
            environment: System.shared.env.append(":/usr/local/bin", to: "PATH")
        )
        
        var command = [
            carthage,
            "checkout"
        ]
        
        if CLI.arguments.carthage.SSH {
            command.append("--use-ssh")
        }
        
        if CLI.arguments.carthage.submodules {
            command.append("--use-submodules")
        }
        
        let directory = CLI.arguments.carthage.projectDirectory ?? CLI.arguments.path
        
        command.append("--project-directory")
        command.append(directory.pathString)

        try System.shared.runAndPrint(
            command,
            verbose: CLI.arguments.verbose,
            environment: System.shared.env
        )
        
    }

}

extension Dictionary where Key == String, Value == String {
    
    func append(_ value: String, to key: String) -> Dictionary {
        var o = self
        o[key]?.append(value)
        return o
    }
    
}
