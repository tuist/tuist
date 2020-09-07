import Foundation
import RxBlocking
import Signals
import TSCBasic
import TuistCore
import TuistSupport
import TuistDoc

// MARK: - DocServicing

protocol DocServicing {
    func run(path: AbsolutePath) throws
}

// MARK: - DocService

struct DocService {
    private static var temporaryDirectory: AbsolutePath?
    
    private let projectGenerator: ProjectGenerating
    private let swiftDocController: SwiftDocControlling
    private let swiftDocServer: SwiftDocServing
    private let opener: Opening
    private let fileHandler: FileHandling

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         swiftDocController: SwiftDocControlling = SwiftDocController(),
         swiftDocServer: SwiftDocServing = SwiftDocServer(),
         opener: Opening = Opener(),
         fileHandler: FileHandling = FileHandler())
    {
        self.projectGenerator = projectGenerator
        self.swiftDocController = swiftDocController
        self.swiftDocServer = swiftDocServer
        self.opener = opener
        self.fileHandler = fileHandler
    }

    func run(path: AbsolutePath, target targetName: String) throws {
        let (_, graph, _) = try projectGenerator.loadProject(path: path)
        
        guard let path = graph.targetPath(name: targetName) else {
            throw Error.targetNotFound(name: targetName)
        }
                        
        try withTemporaryDirectory { generationDirectory in
            DocService.temporaryDirectory = generationDirectory
            
            try swiftDocController.generate(
                format: .html,
                moduleName: targetName,
                outputDirectory: generationDirectory.pathString,
                sourcesPath: "\(path)"
            )

            let indexPath = generationDirectory.appending(component: "index.html")
            try System.shared.run(["open", generationDirectory.pathString])
            
            guard fileHandler.exists(indexPath) else {
                throw Error.documentationNotGenerated
            }
            
            Signals.trap(signals: [.int, .abrt]) { _ in
                // swiftlint:disable:next force_try
                try! DocService.temporaryDirectory.map(FileHandler.shared.delete)
                exit(0)
            }
            
            logger.pretty("Opening the documentation. Press \(.keystroke("CTRL + C")) once you are done.")
            try swiftDocServer.serve(path: generationDirectory, port: 4040)
        }
    }
}

extension Graph {
    func targetPath(name: String) -> AbsolutePath? {
        return targets.flatMap { $0.value }.first(where: { $0.name == name })?.path
    }
}

// MARK: - Error

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
