import Basic
import Foundation
import TuistCore

enum PlaygroundGenerationError: FatalError, Equatable {
    case alreadyExisting(AbsolutePath)

    var description: String {
        switch self {
        case let .alreadyExisting(path):
            return "A playground already exists at path \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .alreadyExisting: return .abort
        }
    }

    static func == (lhs: PlaygroundGenerationError, rhs: PlaygroundGenerationError) -> Bool {
        switch (lhs, rhs) {
        case let (.alreadyExisting(lhsPath), .alreadyExisting(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

protocol PlaygroundGenerating: AnyObject {
    func generate(path: AbsolutePath,
                  name: String,
                  platform: Platform,
                  content: String) throws
}

final class PlaygroundGenerator: PlaygroundGenerating {
    // MARK: - Attributes

    private let fileHandler: FileHandling

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    func generate(path: AbsolutePath,
                  name: String,
                  platform: Platform,
                  content: String = PlaygroundGenerator.defaultContent()) throws {
        let playgroundPath = path.appending(component: "\(name).playground")

        if fileHandler.exists(playgroundPath) {
            throw PlaygroundGenerationError.alreadyExisting(playgroundPath)
        }

        try fileHandler.createFolder(playgroundPath)

        let xcplaygroundPath = playgroundPath.appending(component: "contents.xcplayground")
        let contentsPath = playgroundPath.appending(component: "Contents.swift")

        try content.write(to: contentsPath.url, atomically: true, encoding: .utf8)
        try PlaygroundGenerator.xcplaygroundContent(platform: platform)
            .write(to: xcplaygroundPath.url,
                   atomically: true,
                   encoding: .utf8)
    }

    static func defaultContent() -> String {
        return """
        //: Playground - noun: a place where people can play
        
        import Foundation
        
        """
    }

    static func xcplaygroundContent(platform: Platform) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <playground version='5.0' target-platform='\(platform.rawValue.lowercased())'>
        <timeline fileName='timeline.xctimeline'/>
        </playground>
        """
    }
}
