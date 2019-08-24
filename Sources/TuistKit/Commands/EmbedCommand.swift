import Basic
import Foundation
import SPMUtility
import TuistCore

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

    // MARK: - Init

    convenience init() {
        self.init(embedder: FrameworkEmbedder(),
                  parser: ArgumentParser(usage: "embed", overview: ""))
    }

    init(embedder: FrameworkEmbedding,
         parser: ArgumentParser) {
        self.embedder = embedder
        self.parser = parser
    }

    func run(arguments: [String]) throws {
        guard let pathString = arguments.first else {
            throw EmbedCommandError.missingFrameworkPath
        }
        let path = RelativePath(pathString)
        Printer.shared.print("Embedding framework \(path.pathString)")
        try embedder.embed(path: path)
        Printer.shared.print(success: "Framework embedded")
    }
}
