import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

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
    ///   - device: An optional device specifier to use when building the scheme.
    ///   - osVersion: An optional OS number to use when building the scheme.
    ///   - graphTraverser: The Graph traverser.
    func buildTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        device: String?,
        osVersion: Version?,
        graphTraverser: GraphTraversing
    ) async throws
}

public enum TargetBuilderError: FatalError {
    case schemeWithoutBuildableTargets(scheme: String)
    case buildProductsNotFound(path: String)
    case cantDeterminePlatform(target: Target)

    public var type: ErrorType {
        switch self {
        case .schemeWithoutBuildableTargets:
            return .abort
        case .buildProductsNotFound:
            return .bug
        case .cantDeterminePlatform:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .buildProductsNotFound(path):
            return "The expected build products at \(path) were not found."
        case let .cantDeterminePlatform(target):
            return "Only single platform targets supported. The target \(target.name) specifies multiple supported platforms (\(target.supportedPlatforms.map(\.rawValue).joined(separator: ", ")))."
        }
    }
}

public final class TargetBuilder: TargetBuilding {
    private let buildGraphInspector: BuildGraphInspecting
    private let xcodeBuildController: XcodeBuildControlling
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let simulatorController: SimulatorControlling

    public init(
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
        simulatorController: SimulatorControlling = SimulatorController()
    ) {
        self.buildGraphInspector = buildGraphInspector
        self.xcodeBuildController = xcodeBuildController
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.simulatorController = simulatorController
    }

    public func buildTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        scheme: Scheme,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        device: String?,
        osVersion: Version?,
        graphTraverser: GraphTraversing
    ) async throws {
        logger.log(level: .notice, "Building scheme \(scheme.name)", metadata: .section)

        guard let platform = target.target.exclusivePlatform else {
            throw TargetBuilderError.cantDeterminePlatform(target: target.target)
        }

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
            version: osVersion,
            deviceName: device,
            graphTraverser: graphTraverser,
            simulatorController: simulatorController
        )

        try await xcodeBuildController
            .build(
                .workspace(workspacePath),
                scheme: scheme.name,
                destination: destination,
                clean: clean,
                arguments: buildArguments
            )
            .printFormattedOutput()

        if let buildOutputPath = buildOutputPath {
            let configuration = configuration ?? target.project.settings.defaultDebugBuildConfiguration()?
                .name ?? BuildConfiguration.debug.name
            try copyBuildProducts(
                to: buildOutputPath,
                projectPath: workspacePath,
                platform: platform,
                configuration: configuration
            )
        }
    }

    private func copyBuildProducts(
        to outputPath: AbsolutePath,
        projectPath: AbsolutePath,
        platform: TuistGraph.Platform,
        configuration: String
    ) throws {
        let xcodeSchemeBuildPath = try xcodeProjectBuildDirectoryLocator.locate(
            platform: platform,
            projectPath: projectPath,
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

        try FileHandler.shared
            .contentsOfDirectory(xcodeSchemeBuildPath)
            .forEach { product in
                let productOutputPath = buildOutputPath.appending(component: product.basename)
                if FileHandler.shared.exists(productOutputPath) {
                    try FileHandler.shared.delete(productOutputPath)
                }

                try FileHandler.shared.copy(from: product, to: productOutputPath)
            }
    }
}
