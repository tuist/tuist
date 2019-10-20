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
    func checkout() throws
    
    /// Runs 'carthage build' to build all of the downstream dependencies
    ///
    /// - Parameter graph: Project graph.
    /// - Throws: An error if the installation of the checkout fails.
    func build(graph: Graphing) throws
}

final class CarthageInteractor: CarthageInteracting {
    
    func checkout() throws {
        
        let directory = CLI.arguments.carthage.projectDirectory ?? CLI.arguments.path

        if FileHandler.shared.exists(directory.appending(components: "Cartfile")) == false {
            return
        }

        var command = [
            try carthage(),
            "checkout"
        ]
        
        if CLI.arguments.carthage.SSH {
            command.append("--use-ssh")
        }
        
        if CLI.arguments.carthage.submodules {
            command.append("--use-submodules")
        }
        
        
        command.append("--project-directory")
        command.append(directory.pathString)

        try System.shared.runAndPrint(
            command,
            verbose: CLI.arguments.verbose,
            environment: System.shared.env
        )
        
    }
    
    func build(graph: Graphing) throws {

        let configuration = ProcessInfo.processInfo.environment["CONFIGURATION"] ?? "Debug"

        var command = [
            try carthage(),
            "build",
            "--configuration",
            configuration,
            "--cache-builds"
        ]
        
        let platforms = Set(graph.targets.reduce([Platform]()) { sum, next in
            return sum + [ next.target.platform ]
        })
        
        command.append("--platform")
        command.append(platforms.map(\.caseValue).joined(separator: ","))
        
        let directory = CLI.arguments.carthage.projectDirectory ?? CLI.arguments.path
        
        command.append("--project-directory")
        command.append(directory.pathString)
        
        try System.shared.runAndPrint(
            command,
            verbose: CLI.arguments.verbose,
            environment: System.shared.env
        )
        
    }
    
    private func carthage() throws -> String {
        return try System.shared.which(
            "carthage",
            environment: System.shared.env.append(":/usr/local/bin", to: "PATH")
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
