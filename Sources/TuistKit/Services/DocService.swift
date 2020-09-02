import Foundation
import RxBlocking
import Signals
import TSCBasic
import TuistCore
import TuistSupport

protocol DocServicing {
    func run(path: AbsolutePath) throws
}

struct DocService {
    private static var temporaryDirectory: AbsolutePath?
    private let projectGenerator: ProjectGenerating
    private let binaryLocator: BinaryLocating
    private let opener: Opening
    private let fileHandler: FileHandling

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         binaryLocator: BinaryLocating = BinaryLocator(),
         opener: Opening = Opener(),
         fileHandler: FileHandling = FileHandler())
    {
        self.projectGenerator = projectGenerator
        self.binaryLocator = binaryLocator
        self.opener = opener
        self.fileHandler = fileHandler
    }

    func run(path: AbsolutePath, target targetName: String) throws {
        let swiftDocPath = try binaryLocator.swiftDocPath()

        let (_, graph, _) = try projectGenerator.loadProject(path: path)
        let targets = graph.targets
            .flatMap { $0.value }
            .filter { !$0.dependsOnXCTest }
            .map { (path: $0.path, name: $0.name) }

        guard let module = targets.first(where: { $0.name == targetName }) else {
            throw Error.targetNotFound(name: targetName)
        }
                        
        try withTemporaryDirectory { generationDirectory in
            DocService.temporaryDirectory = generationDirectory
            
            let arguments = [swiftDocPath.pathString,
                             "generate",
                             "--format", "html",
                             "--module-name", module.name,
                             "--output", generationDirectory.pathString,
                             "--base-url", "./",
                             "\(module.path)"]
            
            _ = try System.shared.observable(arguments)
                .mapToString()
                .print()
                .toBlocking()
                .last()

            let indexPath = generationDirectory.appending(component: "index.html")
            
            guard fileHandler.exists(indexPath) else {
                throw Error.documentationNotGenerated
            }

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

extension DocService {
    enum Error: FatalError {
        case targetNotFound(name: String)
        case documentationNotGenerated
        
        var description: String {
            switch self {
            case let .targetNotFound(name):
                return "The target \(name) is not visible in the current project."
            case .documentationNotGenerated:
                return "The documentation was not generated. Problably the provided target does not have public symbols."
            }
        }
        
        var type: ErrorType {
            switch self {
            case .targetNotFound:
                return .abort
            case .documentationNotGenerated:
                return .abort
            }
        }
    }
}
