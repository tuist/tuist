import Foundation
import RxBlocking
import Signals
import TSCBasic
import TuistCore
import TuistDoc
import TuistSupport

// MARK: - DocServiceError

enum DocServiceError: FatalError, Equatable {
    case targetNotFound(name: String)
    case documentationNotGenerated
    case invalidHostURL(urlString: String, port: UInt16)

    var description: String {
        switch self {
        case let .targetNotFound(name):
            return "The target \(name) is not visible in the current project."
        case .documentationNotGenerated:
            return "The documentation was not generated. Problably the provided target does not have public symbols."
        case let .invalidHostURL(url, port):
            return "\(url):\(port) is not a valid URL"
        }
    }

    var type: ErrorType {
        switch self {
        case .targetNotFound:
            return .abort
        case .documentationNotGenerated:
            return .abort
        case .invalidHostURL:
            return .bug
        }
    }
}

// MARK: - DocServicing

protocol DocServicing {
    func run(path: AbsolutePath) throws
}

// MARK: - DocService

final class DocService {
    private static var temporaryDirectory: AbsolutePath?

    private let projectGenerator: ProjectGenerating
    private let swiftDocController: SwiftDocControlling
    private let swiftDocServer: SwiftDocServing

    /// Utility to work with files
    private let fileHandler: FileHandling
    /// Utility to open files
    private let opener: Opening

    /// Semaphore to block the execution
    private let semaphore: Semaphoring

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         swiftDocController: SwiftDocControlling = SwiftDocController(),
         swiftDocServer: SwiftDocServing = SwiftDocServer(),
         fileHandler: FileHandling = FileHandler.shared,
         opener: Opening = Opener(),
         semaphore: Semaphoring = Semaphore())
    {
        self.projectGenerator = projectGenerator
        self.swiftDocController = swiftDocController
        self.swiftDocServer = swiftDocServer
        self.fileHandler = fileHandler
        self.opener = opener
        self.semaphore = semaphore
    }

    func run(project path: AbsolutePath, target targetName: String) throws {
        let (_, graph, _) = try projectGenerator.loadProject(path: path)

        let targets = graph.targets(at: path)
            .filter { !$0.dependsOnXCTest }
            .map { $0.target }

        guard let target = targets.first(where: { $0.name == targetName }) else {
            throw DocServiceError.targetNotFound(name: targetName)
        }

        let sources = target.sources.map(\.path)
        let format: SwiftDocFormat = .html
        let indexName = "index.html"
        let port: UInt16 = 4040

        guard let baseURL = URL(string: type(of: swiftDocServer).baseURL.appending(":\(port)")) else {
            throw DocServiceError.invalidHostURL(urlString: type(of: swiftDocServer).baseURL, port: port)
        }

        try withTemporaryDirectory { generationDirectory in
            DocService.temporaryDirectory = generationDirectory

            try swiftDocController.generate(
                format: format,
                moduleName: targetName,
                baseURL: baseURL.absoluteString,
                outputDirectory: generationDirectory.pathString,
                sourcesPaths: sources
            )

            let indexPath = generationDirectory.appending(component: indexName)

            guard fileHandler.exists(indexPath) else {
                throw DocServiceError.documentationNotGenerated
            }

            Signals.trap(signals: [.int, .abrt]) { _ in
                try? DocService.temporaryDirectory.map(FileHandler.shared.delete)
                exit(0)
            }

            try swiftDocServer.serve(path: generationDirectory, port: port)

            let urlPath = baseURL.appendingPathComponent(indexName)
            logger.pretty("Opening the documentation. Press \(.keystroke("CTRL + C")) once you are done.")
            try opener.open(url: urlPath)

            semaphore.wait()
        }
    }
}

// MARK: - Semaphoring

protocol Semaphoring {
    func wait()
}

struct Semaphore: Semaphoring {
    let semaphore = DispatchSemaphore(value: 0)

    func wait() {
        semaphore.wait()
    }
}
