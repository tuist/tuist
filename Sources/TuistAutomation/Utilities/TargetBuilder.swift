import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol TargetBuilding {
    /// Builds a provided target.
    ///
    /// - Parameters:
    ///   - target: The value graph target where the scheme is defined.
    ///   - workspacePath: The path to the `.xcworkspace` where the target is defined.
    ///   - schemeName: The name of the scheme where the target is defined.
    ///   - clean: Whether to clean the project before running.
    ///   - configuration: The configuration to use while building the scheme.
    ///   - buildOutputPath: An optional path to copy the build products to.
    func buildTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        schemeName: String,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?
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

    public init(
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator()
    ) {
        self.buildGraphInspector = buildGraphInspector
        self.xcodeBuildController = xcodeBuildController
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
    }

    public func buildTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        schemeName: String,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?
    ) async throws {
        logger.log(level: .notice, "Building scheme \(schemeName)", metadata: .section)

        let buildArguments = buildGraphInspector.buildArguments(
            project: target.project,
            target: target.target,
            configuration: configuration,
            skipSigning: false
        )

        try await xcodeBuildController
            .build(
                .workspace(workspacePath),
                scheme: schemeName,
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
                platform: target.target.platform,
                configuration: configuration
            )
        }
    }

    private func copyBuildProducts(
        to outputPath: AbsolutePath,
        projectPath: AbsolutePath,
        platform: Platform,
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
