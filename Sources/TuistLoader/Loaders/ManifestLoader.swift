import Basic
import Foundation
import ProjectDescription
import TuistSupport
import RxBlocking
import RxSwift
public enum ManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)

    public static func manifestNotFound(_ path: AbsolutePath) -> ManifestLoaderError {
        .manifestNotFound(nil, path)
    }

    public var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.pathString)"
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.pathString)"
        case let .manifestNotFound(manifest, path):
            return "\(manifest?.fileName ?? "Manifest") not found at path \(path.pathString)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        case .projectDescriptionNotFound:
            return .bug
        case .manifestNotFound:
            return .abort
        }
    }

    // MARK: - Equatable

    public static func == (lhs: ManifestLoaderError, rhs: ManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.projectDescriptionNotFound(lhsPath), .projectDescriptionNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.unexpectedOutput(lhsPath), .unexpectedOutput(rhsPath)):
            return lhsPath == rhsPath
        case let (.manifestNotFound(lhsManifest, lhsPath), .manifestNotFound(rhsManifest, rhsPath)):
            return lhsManifest == rhsManifest && lhsPath == rhsPath
        default:
            return false
        }
    }
}

public protocol ManifestLoading {
    /// Loads the Config.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the Config.swift file.
    /// - Returns: Loaded Config.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config

    /// Loads the Project.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the Project.swift.
    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project

    /// Loads the Workspace.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the Workspace.swift
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace

    /// Loads the Setup.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the Setup.swift.
    func loadSetup(at path: AbsolutePath) throws -> [Upping]

    /// Loads the Template.swift in the given directory.
    /// - Parameters:
    ///     - path: Path to the directory that contains the Template.swift
    func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returend.
    func manifests(at path: AbsolutePath) -> Set<Manifest>
}

public class ManifestLoader: ManifestLoading {
    // MARK: - Attributes

    let resourceLocator: ResourceLocating
    let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    let manifestFilesLocator: ManifestFilesLocating
    private let decoder: JSONDecoder

    // MARK: - Init

    public convenience init() {
        self.init(resourceLocator: ResourceLocator(),
                  projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilder(),
                  manifestFilesLocator: ManifestFilesLocator())
    }

    init(resourceLocator: ResourceLocating,
         projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding,
         manifestFilesLocator: ManifestFilesLocating) {
        self.resourceLocator = resourceLocator
        self.projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilder
        self.manifestFilesLocator = manifestFilesLocator
        decoder = JSONDecoder()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        Set(manifestFilesLocator.locate(at: path).map { $0.0 })
    }

    public func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config {
        try loadManifest(.config, at: path)
    }

    public func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        try loadManifest(.project, at: path)
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        try loadManifest(.workspace, at: path)
    }

    public func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template {
        try loadManifest(.template, at: path)
    }

    public func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        let setupPath = path.appending(component: Manifest.setup.fileName)
        guard FileHandler.shared.exists(setupPath) else {
            throw ManifestLoaderError.manifestNotFound(.setup, path)
        }

        let setup = try loadManifestData(at: setupPath)
        let setupJson = try JSON(data: setup)
        let actionsJson: [JSON] = try setupJson.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path)
        }
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(_ manifest: Manifest, at path: AbsolutePath) throws -> T {
        var fileNames = [manifest.fileName]
        if let deprecatedFileName = manifest.deprecatedFileName {
            fileNames.insert(deprecatedFileName, at: 0)
        }

        for fileName in fileNames {
            let manifestPath = path.appending(component: fileName)
            if !FileHandler.shared.exists(manifestPath) { continue }
            let data = try loadManifestData(at: manifestPath)
            return try decoder.decode(T.self, from: data)
        }

        throw ManifestLoaderError.manifestNotFound(manifest, path)
    }

    private func loadManifestData(at path: AbsolutePath) throws -> Data {
        let projectDescriptionPath = try resourceLocator.projectDescription()

        var arguments: [String] = [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.pathString,
            "-L", projectDescriptionPath.parentDirectory.pathString,
            "-F", projectDescriptionPath.parentDirectory.pathString,
            "-lProjectDescription",
        ]

        // Helpers
        let projectDesciptionHelpersModulePath = try projectDescriptionHelpersBuilder.build(at: path, projectDescriptionPath: projectDescriptionPath)
        if let projectDesciptionHelpersModulePath = projectDesciptionHelpersModulePath {
            arguments.append(contentsOf: [
                "-I", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-L", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-F", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-lProjectDescriptionHelpers",
            ])
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = try System.shared.observable(arguments)
            .do(onNext: { event in
                switch event {
                case .standardError(let data):
                    if let string = String(data: data, encoding: .utf8) {
                        logger.error("\(string)")
                    }
                default:
                    break
                }
            })
            .toBlocking()
            .first()
        
        if let result = result, case let SystemEvent.standardOutput(output) = result {
            return output
        }
        throw ManifestLoaderError.unexpectedOutput(path)
    }
}
