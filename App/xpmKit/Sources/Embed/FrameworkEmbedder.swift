import Basic
// Reference: https://github.com/CocoaPods/CocoaPods/blob/master/lib/cocoapods/generator/embed_frameworks_script.rb
import Foundation

enum FrameworkEmbedderError: FatalError {
    case missingFramework
    case missingEnvironment

    var type: ErrorType {
        switch self {
        case .missingFramework:
            return .abort
        case .missingEnvironment:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .missingFramework:
            return "A framework needs to be specified."
        case .missingEnvironment:
            return "Running xpm-embed outside Xcode build phases is not allowed."
        }
    }
}

/// Embeds the input framework into the built product.
public class FrameworkEmbedder {
    /// Context.
    private let context: CommandsContexting

    /// Constructor
    public convenience init() {
        self.init(context: CommandsContext())
    }

    init(context: CommandsContexting) {
        self.context = context
    }

    /// Embeds the given framework into the built product.
    ///
    /// - Parameters:
    ///   - frameworkPath: relative path to the framework.
    ///   - environment: XcodeBuild environment.
    func embed(frameworkPath: RelativePath,
               environment: XcodeBuild.Environment) throws {
        let configDir = AbsolutePath(environment.configurationBuildDir)
        let frameworksPath = RelativePath(environment.frameworksFolderPath)
        let builtProductsDir = AbsolutePath(environment.builtProductsDir)
        let srcRoot = AbsolutePath(environment.srcRoot)
        try context.fileHandler.createFolder(configDir.appending(frameworksPath))
        let frameworkPath = srcRoot.appending(frameworkPath)
    }

    /// Embeds the passed framewok into the built product.
    public func embed() {
        do {
            if CommandLine.arguments.count < 2 {
                throw FrameworkEmbedderError.missingFramework
            }
            guard let environment = XcodeBuild.Environment() else {
                throw FrameworkEmbedderError.missingEnvironment
            }
            try embed(frameworkPath: RelativePath(CommandLine.arguments[1]),
                      environment: environment)
        } catch let error as FatalError {
            context.errorHandler.fatal(error: error)
        } catch {
            context.errorHandler.fatal(error: UnhandledError(error: error))
        }
    }
}
