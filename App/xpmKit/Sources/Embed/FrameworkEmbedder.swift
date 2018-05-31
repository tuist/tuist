import Basic
// Reference: https://github.com/CocoaPods/CocoaPods/blob/master/lib/cocoapods/generator/embed_frameworks_script.rb
import Foundation

enum FrameworkEmbedderError: FatalError {
    case missingFramework
    
    var type: ErrorType {
        switch self {
        case .missingFramework:
            return .bug
        }
    }
    
    var description: String {
        switch self {
        case .missingFramework:
            return "A framework needs to be specified"
        }
    }
}

/// Embeds the input framework into the built product.
public class FrameworkEmbedder {
    private let fileHandler: FileHandling

    /// Constructor
    public convenience init() {
        self.init(fileHandler: FileHandler())
    }

    init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler
    }

    public func embed(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        if CommandLine.arguments.count < 2 {
            throw FrameworkEmbedderError.missingFramework
        }
        let frameworkRelativePath = RelativePath(CommandLine.arguments[1])
        if environment["FRAMEWORKS_FOLDER_PATH"] == nil {
            return
        }
        guard let configDirString = environment["CONFIGURATION_BUILD_DIR"] else {
            return
        }
        guard let frameworksPathString = environment["FRAMEWORKS_FOLDER_PATH"] else {
            return
        }
        guard let builtProductsDirString = environment["BUILT_PRODUCTS_DIR"] else {
            return
        }
        guard let srcRootString = environment["SRCROOT"] else {
            return
        }
        let configDir = AbsolutePath(configDirString)
        let frameworksPath = RelativePath(frameworksPathString)
        let builtProductsDir = AbsolutePath(builtProductsDirString)
        let srcRoot = AbsolutePath(srcRootString)
        try fileHandler.createFolder(configDir.appending(frameworksPath))
        let frameworkPath = srcRoot.appending(frameworkRelativePath)
    }
}
