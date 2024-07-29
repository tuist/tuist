import FileSystem
import Path
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

public protocol TargetBuilding {
    /// Builds a provided target.
    ///
    /// - Parameters:
    ///   - target: The value graph target where the scheme is defined.
    ///   - workspacePath: The path to the `.xcworkspace` where the target is defined.
    ///   - scheme: The scheme where the target is defined.
    ///   - clean: Whether to clean the project before running.
    ///   - configuration: The configuration to use while building the scheme.
    ///   - buildOutputPath: An optional path to copy the build products to.
    ///   - derivedDataPath: An optional path for derived data.
    ///   - device: An optional device specifier to use when building the scheme.
    ///   - osVersion: An optional OS number to use when building the scheme.
    ///   - graphTraverser: The Graph traverser.
    ///   - passthroughXcodeBuildArguments: The passthrough xcodebuild arguments to pass to xcodebuild
    func buildTarget(
        _ target: GraphTarget,
        platform: XcodeGraph.Platform,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        device: String?,
        osVersion: XcodeGraph.Version?,
        rosetta: Bool,
        graphTraverser: GraphTraversing,
        passthroughXcodeBuildArguments: [String]
    ) async throws
}

public enum TargetBuilderError: FatalError {
    case schemeWithoutBuildableTargets(scheme: String)
    case buildProductsNotFound(path: String)

    public var type: ErrorType {
        switch self {
        case .schemeWithoutBuildableTargets:
            return .abort
        case .buildProductsNotFound:
            return .bug
        }
    }

    public var description: String {
        switch self {
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .buildProductsNotFound(path):
            return "The expected build products at \(path) were not found."
        }
    }
}

public final class TargetBuilder: TargetBuilding {
    private let buildGraphInspector: BuildGraphInspecting
    private let xcodeBuildController: XcodeBuildControlling
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let simulatorController: SimulatorControlling
    private let fileSystem: FileSystem
    public init(
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
        simulatorController: SimulatorControlling = SimulatorController(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.buildGraphInspector = buildGraphInspector
        self.xcodeBuildController = xcodeBuildController
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.simulatorController = simulatorController
        self.fileSystem = fileSystem
    }

    public func buildTarget(
        _ target: GraphTarget,
        platform: XcodeGraph.Platform,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: AbsolutePath?,
        device: String?,
        osVersion: XcodeGraph.Version?,
        rosetta: Bool,
        graphTraverser: GraphTraversing,
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        logger.log(level: .notice, "Building scheme \(scheme.name)", metadata: .section)

        let buildArguments = buildGraphInspector.buildArguments(
            project: target.project,
            target: target.target,
            configuration: configuration,
            skipSigning: false
        )

        let destination = try await XcodeBuildDestination.find(
            for: target.target,
            on: platform,
            scheme: scheme,
            version: osVersion.map { try .init(versionString: $0.description) },
            deviceName: device,
            graphTraverser: graphTraverser,
            simulatorController: simulatorController
        )

        try await xcodeBuildController
            .build(
                .workspace(workspacePath),
                scheme: scheme.name,
                destination: destination,
                rosetta: rosetta,
                derivedDataPath: derivedDataPath,
                clean: clean,
                arguments: buildArguments,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
            )

        if let buildOutputPath {
            let configuration = configuration ?? target.project.settings.defaultDebugBuildConfiguration()?
                .name ?? BuildConfiguration.debug.name
            try await copyBuildProducts(
                to: buildOutputPath,
                projectPath: workspacePath,
                derivedDataPath: derivedDataPath,
                platform: platform,
                configuration: configuration
            )
        }
    }

    private func copyBuildProducts(
        to outputPath: AbsolutePath,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        platform: XcodeGraph.Platform,
        configuration: String
    ) async throws {
        let xcodeSchemeBuildPath = try xcodeProjectBuildDirectoryLocator.locate(
            platform: platform,
            projectPath: projectPath,
            derivedDataPath: derivedDataPath,
            configuration: configuration
        )
        guard FileHandler.shared.exists(xcodeSchemeBuildPath) else {
            throw TargetBuilderError.buildProductsNotFound(path: xcodeSchemeBuildPath.pathString)
        }

        let buildOutputPath = outputPath.appending(component: xcodeSchemeBuildPath.basename)
        if !FileHandler.shared.exists(buildOutputPath) {
            try FileHandler.shared.createFolder(buildOutputPath)
        }
        logger.log(level: .notice, "Copying build products to \(buildOutputPath.pathString)", metadata: .subsection)

        for product in try FileHandler.shared.contentsOfDirectory(xcodeSchemeBuildPath) {
            let productOutputPath = buildOutputPath.appending(component: product.basename)
            if FileHandler.shared.exists(productOutputPath) {
                try await fileSystem.remove(productOutputPath)
            }

            try FileHandler.shared.copy(from: product, to: productOutputPath)
        }
    }
}
