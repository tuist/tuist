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

    func run(path: AbsolutePath) throws {
        let (project, _, _) = try projectGenerator.loadProject(path: path)
        let targets = project.targets.filter { !$0.product.testsBundle }
        let sources = Set(targets.flatMap { $0.sources }.map(\.path).map(\.parentDirectory))
        let swiftDocPath = try binaryLocator.swiftDocPath()

        try withTemporaryDirectory { generationDirectory in
            DocService.temporaryDirectory = generationDirectory

            var arguments = [swiftDocPath.pathString,
                             "generate",
                             "--format", "html",
                             "--module-name", project.name,
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
            // TODO: Extend package to include the binary.

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
