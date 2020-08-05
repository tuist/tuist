import Foundation
import PathKit
import TSCBasic
import TuistCore
import TuistSupport
import XcodeProj

enum LinkGeneratorError: FatalError, Equatable {
    case missingProduct(name: String)
    case missingReference(path: AbsolutePath)
    case missingConfigurationList(targetName: String)

    var description: String {
        switch self {
        case let .missingProduct(name):
            return "Couldn't find a reference for the product \(name)."
        case let .missingReference(path):
            return "Couldn't find a reference for the file at path \(path.pathString)."
        case let .missingConfigurationList(targetName):
            return "The target \(targetName) doesn't have a configuration list."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingProduct, .missingConfigurationList, .missingReference:
            return .bug
        }
    }

    static func == (lhs: LinkGeneratorError, rhs: LinkGeneratorError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingProduct(lhsName), .missingProduct(rhsName)):
            return lhsName == rhsName
        case let (.missingReference(lhsPath), .missingReference(rhsPath)):
            return lhsPath == rhsPath
        case let (.missingConfigurationList(lhsName), .missingConfigurationList(rhsName)):
            return lhsName == rhsName
        default:
            return false
        }
    }
}

protocol LinkGenerating: AnyObject {
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       pbxproj: PBXProj,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graph) throws
}

/// When generating build settings like "framework search path", some of the path might be relative to paths
/// defined by environment variables like $(DEVELOPER_FRAMEWORKS_DIR). This enum represents both
/// types of supported paths.
enum LinkGeneratorPath: Hashable {
    case absolutePath(AbsolutePath)
    case string(String)

    func xcodeValue(sourceRootPath: AbsolutePath) -> String {
        switch self {
        case let .absolutePath(path):
            return "$(SRCROOT)/\(path.relative(to: sourceRootPath).pathString)"
        case let .string(value):
            return value
        }
    }
}

// swiftlint:disable type_body_length
final class LinkGenerator: LinkGenerating {
    /// An instance to locate tuist binaries.
    let binaryLocator: BinaryLocating

    /// Utility that generates the script to embed dynamic frameworks.
    let embedScriptGenerator: EmbedScriptGenerating

    /// Initializes the link generator with its attributes.
    /// - Parameter binaryLocator: An instance to locate tuist binaries.
    /// - Parameter embedScriptGenerator: Utility that generates the script to embed dynamic frameworks.
    init(binaryLocator: BinaryLocating = BinaryLocator(),
         embedScriptGenerator: EmbedScriptGenerating = EmbedScriptGenerator()) {
        self.binaryLocator = binaryLocator
        self.embedScriptGenerator = embedScriptGenerator
    }

    // MARK: - LinkGenerating

    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       pbxproj: PBXProj,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graph) throws {
        let embeddableFrameworks = try graph.embeddableFrameworks(path: path, name: target.name)
        let linkableModules = try graph.linkableDependencies(path: path, name: target.name)

        try setupSearchAndIncludePaths(target: target,
                                       pbxTarget: pbxTarget,
                                       sourceRootPath: sourceRootPath,
                                       path: path,
                                       graph: graph,
                                       linkableModules: linkableModules)

        try generateEmbedPhase(dependencies: embeddableFrameworks,
                               target: target,
                               pbxTarget: pbxTarget,
                               pbxproj: pbxproj,
                               fileElements: fileElements,
                               sourceRootPath: sourceRootPath)

        try generateLinkingPhase(dependencies: linkableModules,
                                 pbxTarget: pbxTarget,
                                 pbxproj: pbxproj,
                                 fileElements: fileElements)

        try generateCopyProductsdBuildPhase(path: path,
                                            target: target,
                                            graph: graph,
                                            pbxTarget: pbxTarget,
                                            pbxproj: pbxproj,
                                            fileElements: fileElements)

        try generatePackages(target: target,
                             pbxTarget: pbxTarget,
                             pbxproj: pbxproj)
    }

    private func setupSearchAndIncludePaths(target: Target,
                                            pbxTarget: PBXTarget,
                                            sourceRootPath: AbsolutePath,
                                            path: AbsolutePath,
                                            graph: Graph,
                                            linkableModules: [GraphDependencyReference]) throws {
        let headersSearchPaths = graph.librariesPublicHeadersFolders(path: path, name: target.name)
        let librarySearchPaths = graph.librariesSearchPaths(path: path, name: target.name)
        let swiftIncludePaths = graph.librariesSwiftIncludePaths(path: path, name: target.name)
        let runPathSearchPaths = graph.runPathSearchPaths(path: path, name: target.name)

        try setupFrameworkSearchPath(dependencies: linkableModules,
                                     pbxTarget: pbxTarget,
                                     sourceRootPath: sourceRootPath)

        try setupHeadersSearchPath(headersSearchPaths,
                                   pbxTarget: pbxTarget,
                                   sourceRootPath: sourceRootPath)

        try setupLibrarySearchPaths(librarySearchPaths,
                                    pbxTarget: pbxTarget,
                                    sourceRootPath: sourceRootPath)

        try setupSwiftIncludePaths(swiftIncludePaths,
                                   pbxTarget: pbxTarget,
                                   sourceRootPath: sourceRootPath)

        try setupRunPathSearchPaths(runPathSearchPaths,
                                    pbxTarget: pbxTarget,
                                    sourceRootPath: sourceRootPath)
    }

    func generatePackages(target: Target,
                          pbxTarget: PBXTarget,
                          pbxproj: PBXProj) throws {
        for dependency in target.dependencies {
            switch dependency {
            case let .package(product: product):
                try pbxTarget.addSwiftPackageProduct(productName: product, pbxproj: pbxproj)
            default:
                break
            }
        }
    }

    func generateEmbedPhase(dependencies: [GraphDependencyReference],
                            target: Target,
                            pbxTarget: PBXTarget,
                            pbxproj: PBXProj,
                            fileElements: ProjectFileElements,
                            sourceRootPath: AbsolutePath) throws {
        let precompiledEmbedPhase = PBXShellScriptBuildPhase(name: "Embed Precompiled Frameworks")
        let embedPhase = PBXCopyFilesBuildPhase(dstSubfolderSpec: .frameworks,
                                                name: "Embed Frameworks")
        pbxproj.add(object: precompiledEmbedPhase)
        pbxproj.add(object: embedPhase)

        pbxTarget.buildPhases.append(precompiledEmbedPhase)
        pbxTarget.buildPhases.append(embedPhase)

        var frameworkReferences: [GraphDependencyReference] = []

        try dependencies.forEach { dependency in
            switch dependency {
            case .framework:
                frameworkReferences.append(dependency)
            case .library:
                // Do nothing
                break
            case let .xcframework(path, _, _, _):
                guard let fileRef = fileElements.file(path: path) else {
                    throw LinkGeneratorError.missingReference(path: path)
                }
                let buildFile = PBXBuildFile(
                    file: fileRef,
                    settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]
                )
                pbxproj.add(object: buildFile)
                embedPhase.files?.append(buildFile)
            case .sdk:
                // Do nothing
                break
            case let .product(target, _):
                guard let fileRef = fileElements.product(target: target) else {
                    throw LinkGeneratorError.missingProduct(name: target)
                }
                let buildFile = PBXBuildFile(file: fileRef,
                                             settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]])
                pbxproj.add(object: buildFile)
                embedPhase.files?.append(buildFile)
            }
        }

        if frameworkReferences.isEmpty {
            precompiledEmbedPhase.shellScript = "echo \"Skipping, nothing to be embedded.\""
        } else {
            let script = try embedScriptGenerator.script(sourceRootPath: sourceRootPath,
                                                         frameworkReferences: frameworkReferences,
                                                         includeSymbolsInFileLists: !target.product.testsBundle)

            precompiledEmbedPhase.shellScript = script.script
            precompiledEmbedPhase.inputPaths = script.inputPaths.map(\.pathString)
            precompiledEmbedPhase.outputPaths = script.outputPaths
        }
    }

    func setupFrameworkSearchPath(dependencies: [GraphDependencyReference],
                                  pbxTarget: PBXTarget,
                                  sourceRootPath: AbsolutePath) throws {
        let precompiledPaths = dependencies.compactMap { $0.precompiledPath }
            .map { LinkGeneratorPath.absolutePath($0.removingLastComponent()) }
        let sdkPaths = dependencies.compactMap { (dependency: GraphDependencyReference) -> LinkGeneratorPath? in
            if case let GraphDependencyReference.sdk(_, _, source) = dependency {
                return LinkGeneratorPath.string(source.frameworkSearchPath)
            } else {
                return nil
            }
        }

        let uniquePaths = Array(Set(precompiledPaths + sdkPaths))
        try setup(setting: "FRAMEWORK_SEARCH_PATHS",
                  paths: uniquePaths,
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupHeadersSearchPath(_ paths: [AbsolutePath],
                                pbxTarget: PBXTarget,
                                sourceRootPath: AbsolutePath) throws {
        try setup(setting: "HEADER_SEARCH_PATHS",
                  paths: paths.map(LinkGeneratorPath.absolutePath),
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupLibrarySearchPaths(_ paths: [AbsolutePath],
                                 pbxTarget: PBXTarget,
                                 sourceRootPath: AbsolutePath) throws {
        try setup(setting: "LIBRARY_SEARCH_PATHS",
                  paths: paths.map(LinkGeneratorPath.absolutePath),
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupSwiftIncludePaths(_ paths: [AbsolutePath],
                                pbxTarget: PBXTarget,
                                sourceRootPath: AbsolutePath) throws {
        try setup(setting: "SWIFT_INCLUDE_PATHS",
                  paths: paths.map(LinkGeneratorPath.absolutePath),
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupRunPathSearchPaths(_ paths: [AbsolutePath],
                                 pbxTarget: PBXTarget,
                                 sourceRootPath: AbsolutePath) throws {
        try setup(setting: "LD_RUNPATH_SEARCH_PATHS",
                  paths: paths.map(LinkGeneratorPath.absolutePath),
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    private func setup(setting name: String,
                       paths: [LinkGeneratorPath],
                       pbxTarget: PBXTarget,
                       sourceRootPath: AbsolutePath) throws {
        guard let configurationList = pbxTarget.buildConfigurationList else {
            throw LinkGeneratorError.missingConfigurationList(targetName: pbxTarget.name)
        }
        guard !paths.isEmpty else {
            return
        }
        let value = SettingValue
            .array(["$(inherited)"] + paths.map { $0.xcodeValue(sourceRootPath: sourceRootPath) }.uniqued().sorted())
        let newSetting = [name: value]
        let helper = SettingsHelper()
        try configurationList.buildConfigurations.forEach { configuration in
            try helper.extend(buildSettings: &configuration.buildSettings, with: newSetting)
        }
    }

    func generateLinkingPhase(dependencies: [GraphDependencyReference],
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              fileElements: ProjectFileElements) throws {
        let buildPhase = PBXFrameworksBuildPhase()
        pbxproj.add(object: buildPhase)
        pbxTarget.buildPhases.append(buildPhase)

        func addBuildFile(_ path: AbsolutePath) throws {
            guard let fileRef = fileElements.file(path: path) else {
                throw LinkGeneratorError.missingReference(path: path)
            }
            let buildFile = PBXBuildFile(file: fileRef)
            pbxproj.add(object: buildFile)
            buildPhase.files?.append(buildFile)
        }

        try dependencies
            .sorted()
            .forEach { dependency in
                switch dependency {
                case let .framework(path, _, _, _, _, _, _, _):
                    try addBuildFile(path)
                case let .library(path, _, _, _, _):
                    try addBuildFile(path)
                case let .xcframework(path, _, _, _):
                    try addBuildFile(path)
                case let .product(target, _):
                    guard let fileRef = fileElements.product(target: target) else {
                        throw LinkGeneratorError.missingProduct(name: target)
                    }
                    let buildFile = PBXBuildFile(file: fileRef)
                    pbxproj.add(object: buildFile)
                    buildPhase.files?.append(buildFile)
                case let .sdk(sdkPath, sdkStatus, _):
                    guard let fileRef = fileElements.sdk(path: sdkPath) else {
                        throw LinkGeneratorError.missingReference(path: sdkPath)
                    }

                    let buildFile = createSDKBuildFile(for: fileRef, status: sdkStatus)
                    pbxproj.add(object: buildFile)
                    buildPhase.files?.append(buildFile)
                }
            }
    }

    func generateCopyProductsdBuildPhase(path: AbsolutePath,
                                         target: Target,
                                         graph: Graph,
                                         pbxTarget: PBXTarget,
                                         pbxproj: PBXProj,
                                         fileElements: ProjectFileElements) throws {
        // If the current target, which is non-shared (e.g., static lib), depends on other focused targets which
        // include Swift code, we must ensure those are treated as dependencies so that Xcode builds the targets
        // in the correct order. Unfortunately, those deps can be part of other projects which would require
        // cross-project references.
        //
        // Thankfully, there's an easy workaround because we can just create a phony copy phase which depends on
        // the outputs of the deps (i.e., the static libs). The copy phase will effectively say "Copy libX.a from
        // Products Dir into Products Dir" which is a nop. To be on the safe side, we're explicitly marking the
        // copy phase as only running for deployment postprocessing (i.e., "Copy only when installing") and
        // disabling deployment postprocessing (it's enabled by default for release builds).
        //
        // This technique also allows resource bundles that reside in different projects to get built ahead of the
        // "Copy Bundle Resources" phase.

        let dependencies = graph.copyProductDependencies(path: path, target: target)

        if !dependencies.isEmpty {
            try generateDependenciesBuildPhase(
                dependencies: dependencies,
                pbxTarget: pbxTarget,
                pbxproj: pbxproj,
                fileElements: fileElements
            )
        }
    }

    private func generateDependenciesBuildPhase(dependencies: [GraphDependencyReference],
                                                pbxTarget: PBXTarget,
                                                pbxproj: PBXProj,
                                                fileElements: ProjectFileElements) throws {
        var files: [PBXBuildFile] = []

        for case let .product(target, _) in dependencies.sorted() {
            guard let fileRef = fileElements.product(target: target) else {
                throw LinkGeneratorError.missingProduct(name: target)
            }

            let buildFile = PBXBuildFile(file: fileRef)
            pbxproj.add(object: buildFile)
            files.append(buildFile)
        }

        // Nothing to link, move on.
        if files.isEmpty {
            return
        }

        let buildPhase = PBXCopyFilesBuildPhase(
            dstPath: nil,
            dstSubfolderSpec: .productsDirectory,
            name: "Dependencies",
            buildActionMask: 8,
            files: files,
            runOnlyForDeploymentPostprocessing: true
        )

        pbxproj.add(object: buildPhase)
        pbxTarget.buildPhases.append(buildPhase)
    }

    func createSDKBuildFile(for fileReference: PBXFileReference, status: SDKStatus) -> PBXBuildFile {
        var settings: [String: Any]?
        if status == .optional {
            settings = ["ATTRIBUTES": ["Weak"]]
        }
        return PBXBuildFile(file: fileReference,
                            settings: settings)
    }
}

private extension XCBuildConfiguration {
    func append(setting name: String, value: String) {
        guard !value.isEmpty else {
            return
        }
        let existing = (buildSettings[name] as? String) ?? "$(inherited)"
        buildSettings[name] = [existing, value].joined(separator: " ")
    }
}

extension PBXTarget {
    func addSwiftPackageProduct(productName: String, pbxproj: PBXProj) throws {
        let productDependency = XCSwiftPackageProductDependency(productName: productName)
        pbxproj.add(object: productDependency)
        packageProductDependencies.append(productDependency)

        // Build file
        let buildFile = PBXBuildFile(product: productDependency)
        pbxproj.add(object: buildFile)

        // Link the product
        guard let frameworksBuildPhase = try frameworksBuildPhase() else {
            throw "No frameworks build phase"
        }

        frameworksBuildPhase.files?.append(buildFile)
    }
}
