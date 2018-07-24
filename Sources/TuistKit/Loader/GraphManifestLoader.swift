import Basic
import Foundation
import TuistCore

enum GraphManifestLoaderError: FatalError {
    case projectDescriptionNotFound(AbsolutePath)
    case frameworksFolderNotFound
    case unexpectedOutput(AbsolutePath)

    var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.asString)."
        case .frameworksFolderNotFound:
            return "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework."
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)."
        }
    }

    var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        default:
            return .abort
        }
    }

    // MARK: - Equatable

    static func == (lhs: GraphManifestLoaderError, rhs: GraphManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.projectDescriptionNotFound(lhsPath), .projectDescriptionNotFound(rhsPath)):
            return lhsPath == rhsPath
        case (.frameworksFolderNotFound, .frameworksFolderNotFound): return true
        case let (.unexpectedOutput(lhsPath), .unexpectedOutput(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

protocol GraphManifestLoading {
    func load(path: AbsolutePath) throws -> JSON
}

class GraphManifestLoader: GraphManifestLoading {

    // MARK: - Attributes

    let moduleLoader: GraphModuleLoading
    let fileAggregator: FileAggregating
    let fileHandler: FileHandling
    let system: Systeming
    let resourceLocator: ResourceLocating

    // MARK: - Init

    init(moduleLoader: GraphModuleLoading = GraphModuleLoader(),
         fileAggregator: FileAggregating = FileAggregator(),
         fileHandler: FileHandling = FileHandler(),
         system: Systeming = System(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.moduleLoader = moduleLoader
        self.fileAggregator = fileAggregator
        self.fileHandler = fileHandler
        self.system = system
        self.resourceLocator = resourceLocator
    }

    func load(path: AbsolutePath) throws -> JSON {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        var arguments: [String] = [
            "xcrun", "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.asString,
            "-L", projectDescriptionPath.parentDirectory.asString,
            "-F", projectDescriptionPath.parentDirectory.asString,
            "-lProjectDescription",
        ]
        let file = try TemporaryFile()
        try fileAggregator.aggregate(moduleLoader.load(path).reversed(), into: file.path)
        arguments.append(file.path.asString)
        arguments.append("--dump")
        let result = system.capture3(arguments, verbose: false)
        try result.throwIfError()
        let jsonString: String! = result.stdout.chuzzle()
        if jsonString == nil {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        let json = try JSON(string: jsonString)
        return json
    }
}
