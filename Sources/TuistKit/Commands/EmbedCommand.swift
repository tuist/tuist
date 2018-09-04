import Basic
import Foundation
import TuistCore
import Utility

enum EmbedCommandError: FatalError {
    case missingFrameworkPath

    var type: ErrorType {
        switch self {
        case .missingFrameworkPath:
            return .bug
        }
    }

    var description: String {
        switch self {
        case .missingFrameworkPath:
            return "The path to the framework is missing."
        }
    }
}

final class EmbedCommand: HiddenCommand {
    // MARK: - HiddenCommand

    static var command: String = "embed"

    // MARK: - Attributes

    private let embedder: FrameworkEmbedding
    private let parser: ArgumentParser
    private let fileHandler: FileHandling
    private let printer: Printing

    // MARK: - Init

    convenience init() {
        self.init(embedder: FrameworkEmbedder(),
                  parser: ArgumentParser(usage: "embed", overview: ""),
                  fileHandler: FileHandler(),
                  printer: Printer())
    }

    init(embedder: FrameworkEmbedding,
         parser: ArgumentParser,
         fileHandler: FileHandling,
         printer: Printing) {
        self.embedder = embedder
        self.parser = parser
        self.fileHandler = fileHandler
        self.printer = printer
    }

    func run(arguments: [String]) throws {
        guard let pathString = arguments.first else {
            throw EmbedCommandError.missingFrameworkPath
        }
        let path = RelativePath(pathString)
        printer.print("Embedding framework \(path.asString)")
        try embedder.embed(path: path)
        printer.print(success: "Framework embedded")
    }
}
