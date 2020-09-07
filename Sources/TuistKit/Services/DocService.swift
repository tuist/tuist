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
    private let projectGenerator: ProjectGenerating
    private let swiftDocController: SwiftDocControlling
    private let swiftDocServer: SwiftDocServing
    private let fileHandler: FileHandling

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         swiftDocController: SwiftDocControlling = SwiftDocController(),
         swiftDocServer: SwiftDocServing = SwiftDocServer(),
         fileHandler: FileHandling = FileHandler())
    {
        self.projectGenerator = projectGenerator
        self.swiftDocController = swiftDocController
        self.swiftDocServer = swiftDocServer
        self.fileHandler = fileHandler
    }

    func run(path: AbsolutePath, target targetName: String) throws {
        let (_, graph, _) = try projectGenerator.loadProject(path: path)
        
        guard let path = graph.targetPath(name: targetName) else {
            throw Error.targetNotFound(name: targetName)
        }
                        
        let port: UInt16 = 4040
        let baseURL = swiftDocServer.baseURL.appending(":\(port)")
        
        try withTemporaryDirectory { generationDirectory in
            try swiftDocController.generate(
                format: .html,
                moduleName: targetName,
                baseURL: baseURL,
                outputDirectory: generationDirectory.pathString,
                sourcesPath: "\(path)"
            )
            
            let indexPath = generationDirectory.appending(component: "index.html")
            guard fileHandler.exists(indexPath) else {
                throw Error.documentationNotGenerated
            }
            
            try swiftDocServer.serve(path: generationDirectory, port: port)
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
