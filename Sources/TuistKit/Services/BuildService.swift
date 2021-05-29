import Foundation
import RxBlocking
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistSupport

enum BuildServiceError: FatalError {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutBuildableTargets(scheme: String)
    case buildProductsNotFound(path: AbsolutePath)

    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .buildProductsNotFound(path):
            return "The expected build products at \(path.pathString) were not found."
        }
    }

    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound:
            return .abort
        case .schemeWithoutBuildableTargets:
            return .abort
        case .buildProductsNotFound:
            return .bug
        }
    }
}

final class BuildService {
    /// Generator
    let generator: Generating

    /// Xcode build controller.
    let xcodeBuildController: XcodeBuildControlling

    /// Locator for finding `xcodebuild` output directory.
    let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating

    /// Build graph inspector.
    let buildGraphInspector: BuildGraphInspecting

    init(
        generator: Generating = Generator(contentHasher: CacheContentHasher()),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector()
    ) {
        self.generator = generator
        self.xcodeBuildController = xcodeBuildController
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.buildGraphInspector = buildGraphInspector
    }

    func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        path: AbsolutePath
    ) throws {
        let graph: ValueGraph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try generator.generateWithGraph(path: path, projectOnly: false).1
        } else {
            graph = try generator.load(path: path)
        }
        let graphTraverser = ValueGraphTraverser(graph: graph)

        let buildableSchemes = buildGraphInspector.buildableSchemes(graphTraverser: graphTraverser)

        logger.log(level: .debug, "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))")

        let workspacePath = try buildGraphInspector.workspacePath(directory: path)!

        if let schemeName = schemeName {
            guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                throw BuildServiceError.schemeNotFound(scheme: schemeName, existing: buildableSchemes.map(\.name))
            }

            try buildScheme(
                scheme: scheme,
                graphTraverser: graphTraverser,
                workspacePath: workspacePath,
                clean: clean,
                configuration: configuration,
                buildOutputPath: buildOutputPath
            )
        } else {
            var cleaned: Bool = false
            // Run only buildable entry schemes when specific schemes has not been passed
            let buildableEntrySchemes = buildGraphInspector.buildableEntrySchemes(graphTraverser: graphTraverser)
            try buildableEntrySchemes.forEach {
                try buildScheme(
                    scheme: $0,
                    graphTraverser: graphTraverser,
                    workspacePath: workspacePath,
                    clean: !cleaned && clean,
                    configuration: configuration,
                    buildOutputPath: buildOutputPath
                )
                cleaned = true
            }
        }

        logger.log(level: .notice, "The project built successfully", metadata: .success)
    }

    // MARK: - private

    private func buildScheme(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        workspacePath: AbsolutePath,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?
    ) throws {
        logger.log(level: .notice, "Building scheme \(scheme.name)", metadata: .section)
        guard let (project, target) = buildGraphInspector.buildableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw BuildServiceError.schemeWithoutBuildableTargets(scheme: scheme.name)
        }

        let buildArguments = buildGraphInspector.buildArguments(project: project, target: target, configuration: configuration, skipSigning: false)

        _ = try xcodeBuildController
            .build(
                .workspace(workspacePath),
                scheme: scheme.name,
                clean: clean,
                arguments: buildArguments
            )
            .printFormattedOutput()
            .toBlocking()
            .last()

        if let buildOutputPath = buildOutputPath {
            let configuration = configuration ?? project.settings.defaultDebugBuildConfiguration()?.name ?? BuildConfiguration.debug.name
            try copyBuildProducts(
                to: buildOutputPath,
                workspacePath: workspacePath,
                platform: target.platform,
                configuration: configuration
            )
        }
    }

    private func copyBuildProducts(
        to outputPath: AbsolutePath,
        workspacePath: AbsolutePath,
        platform: Platform,
        configuration: String
    ) throws {
        let xcodeSchemeBuildPath = try xcodeProjectBuildDirectoryLocator.locate(
            platform: platform,
            projectPath: workspacePath,
            configuration: configuration
        )
        guard FileHandler.shared.exists(xcodeSchemeBuildPath) else {
            throw BuildServiceError.buildProductsNotFound(path: xcodeSchemeBuildPath)
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
