import RxBlocking
import TuistCore
import TuistSupport
import TSCBasic

public protocol SwiftDocControlling {
    func generate(format: SwiftDocFormat,
                  moduleName: String,
                  baseURL: String,
                  outputDirectory: String,
                  sourcesPaths paths: [AbsolutePath]) throws
}

public enum SwiftDocFormat: String {
    case html, commonmark
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
                         sourcesPaths paths: [AbsolutePath]) throws
    {
        let swiftDocPath = try binaryLocator.swiftDocPath()

        var arguments = [swiftDocPath.pathString,
                         "generate",
                         "--format", format.rawValue,
                         "--module-name", moduleName,
                         "--base-url", baseURL,
                         "--output", outputDirectory]
        arguments.append(contentsOf: Set(paths.map { $0.dirname }))
        
        logger.pretty("Generating documentation for \(.bold(.raw(moduleName))).")

        _ = try System.shared.observable(arguments)
            .mapToString()
            .print()
            .toBlocking()
            .last()
    }
}
