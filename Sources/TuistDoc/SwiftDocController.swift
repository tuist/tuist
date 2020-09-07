import TuistCore
import TuistSupport
import RxBlocking

public protocol SwiftDocControlling {
    func generate(format: SwiftDocFormat,
                  moduleName: String,
                  baseURL: String,
                  outputDirectory: String,
                  sourcesPath path: String) throws
}

public enum SwiftDocFormat: String {
    case html = "html", commonmark = "commonmark"
}

public struct SwiftDocController: SwiftDocControlling {
    private let binaryLocator: BinaryLocating
    
    public init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    public func generate(format: SwiftDocFormat,
                         moduleName: String,
                         baseURL: String,
                         outputDirectory: String,
                         sourcesPath path: String) throws {
        let swiftDocPath = try binaryLocator.swiftDocPath()

        let arguments = [swiftDocPath.pathString,
                         "generate",
                         "--format", format.rawValue,
                         "--module-name", moduleName,
                         "--base-url", baseURL,
                         "--output", outputDirectory,
                         path]
        
        logger.pretty("Generating documentation for \(.bold(.raw(moduleName))).")

        _ = try System.shared.observable(arguments)
            .mapToString()
            .print()
            .toBlocking()
            .last()
    }
}
