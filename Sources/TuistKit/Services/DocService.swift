import Foundation
import RxBlocking
import Signals
import TSCBasic
import TuistCore
import TuistSupport

enum TargetNotFoundError: FatalError {
    case targetNotFound(name: String)
    
    var description: String {
        switch self {
        case let .targetNotFound(name):
            return "The target \(name) is not visible in the current project."
        }
    }
    
    var type: ErrorType {
        switch self {
        case .targetNotFound:
            return .abort
        }
    }
}

protocol DocServicing {
    func run(path: AbsolutePath) throws
}

struct DocService {
    private static var temporaryDirectory: AbsolutePath?
    let projectGenerator: ProjectGenerating
    let binaryLocator: BinaryLocating
    let opener: Opening

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         binaryLocator: BinaryLocating = BinaryLocator(),
         opener: Opening = Opener())
    {
        self.projectGenerator = projectGenerator
        self.binaryLocator = binaryLocator
        self.opener = opener
    }

    func run(path: AbsolutePath, target: String?) throws {
        let (project, graph, _) = try projectGenerator.loadProject(path: path)
        let targets = project.targets.filter { !$0.product.testsBundle }
        let sources = Set(targets.flatMap { $0.sources }.map(\.path).map(\.parentDirectory))
        let swiftDocPath = try binaryLocator.swiftDocPath()
        
        let moduleName: String
        if let target = target {
            guard let name = graph.target(path: path, name: target)?.name
                    ?? graph.targetDependencies(path: path, name: target).first?.name else {
                throw TargetNotFoundError.targetNotFound(name: target)
            }
            moduleName = name
        } else {
            moduleName = project.name
        }
                
        try withTemporaryDirectory { generationDirectory in
            DocService.temporaryDirectory = generationDirectory

            var arguments = [swiftDocPath.pathString,
                             "generate",
                             "--format", "html",
                             "--module-name", moduleName,
                             "--output", generationDirectory.pathString,
                             "--base-url", "./"]
            arguments.append(contentsOf: sources.map(\.pathString))

            _ = try System.shared.observable(arguments)
                .mapToString()
                .print()
                .toBlocking()
                .last()

            let indexPath = generationDirectory.appending(component: "index.html")
            
            // TODO: If index doesn't exist, it's possible swift-doc threw a warning. Handle it better.

            Signals.trap(signals: [.int, .abrt]) { _ in
                // swiftlint:disable:next force_try
                try! DocService.temporaryDirectory.map(FileHandler.shared.delete)
                exit(0)
            }

            logger.pretty("Opening the documentation. Press \(.keystroke("CTRL + C")) once you are done.")
            try opener.open(path: indexPath, wait: true)
        }
    }
}
