import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport

/// SwiftDoc controller protocol passed in initializers for dependency injection
public protocol SwiftDocControlling {
    /// Generates the documentation for a given module
    /// - Parameters:
    ///   - format: Format of the output
    ///   - moduleName: Name of the target.
    ///   - baseURL: Base URL for all the documentation relative paths
    ///   - outputDirectory: Directory where the documentation will be placed
    ///   - sourcesPaths: Paths to the files to be documented
    func generate(format: SwiftDocFormat,
                  moduleName: String,
                  baseURL: String,
                  outputDirectory: String,
                  sourcesPaths paths: [AbsolutePath]) throws
}

/// Available formats for generating documentation
public enum SwiftDocFormat: String {
    case html, commonmark
}

/// SwiftDoc controller struct that generates the documentation using the SwiftDoc binary.
public struct SwiftDocController: SwiftDocControlling {
    /// Utility to locate a binary
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
