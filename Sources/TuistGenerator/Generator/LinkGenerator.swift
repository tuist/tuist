import Foundation
import PathKit
import TSCBasic
import TuistCore
import TuistGraph
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
}

protocol LinkGenerating: AnyObject {
    func generateLinks(
        target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        path: AbsolutePath,
        sourceRootPath: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws
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
    /// Utility that generates the script to embed dynamic frameworks.
    let embedScriptGenerator: EmbedScriptGenerating

    /// Initializes the link generator with its attributes.
    /// - Parameter embedScriptGenerator: Utility that generates the script to embed dynamic frameworks.
    init(embedScriptGenerator: EmbedScriptGenerating = EmbedScriptGenerator()) {
        self.embedScriptGenerator = embedScriptGenerator
    }

    // MARK: - LinkGenerating

    func generateLinks(
        target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        path: AbsolutePath,
        sourceRootPath: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        try setupSearchAndIncludePaths(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try generateEmbedPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try generateLinkingPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        try generateCopyProductsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements
        )

        try generatePackages(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj
        )
    }

    private func setupSearchAndIncludePaths(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        try setupFrameworkSearchPath(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try setupHeadersSearchPath(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try setupLibrarySearchPaths(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try setupSwiftIncludePaths(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        try setupRunPathSearchPaths(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )
    }

    func generatePackages(
        target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj
    ) throws {
        for dependency in target.dependencies {
            switch dependency {
            case let .package(product: product):
                try pbxTarget.addSwiftPackageProduct(productName: product, pbxproj: pbxproj)
            default:
                break
            }
        }
    }

    // swiftlint:disable:next function_body_length
    func generateEmbedPhase(
        target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let embeddableFrameworks = graphTraverser.embeddableFrameworks(path: path, name: target.name).sorted()

        let embedPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks"
        )

        var frameworkReferences: [GraphDependencyReference] = []

        try embeddableFrameworks.forEach { dependency in
            switch dependency {
            case .framework:
                frameworkReferences.append(dependency)
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
            case let .product(target, _, platformFilter):
                guard let fileRef = fileElements.product(target: target) else {
                    throw LinkGeneratorError.missingProduct(name: target)
                }
                let buildFile = PBXBuildFile(
                    file: fileRef,
                    settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]
                )
                buildFile.platformFilter = platformFilter?.xcodeprojValue
                pbxproj.add(object: buildFile)
                embedPhase.files?.append(buildFile)
            case .library, .bundle, .sdk:
                // Do nothing
                break
            }
        }

        if !frameworkReferences.isEmpty {
            let precompiledEmbedPhase = PBXShellScriptBuildPhase(name: "Embed Precompiled Frameworks")

            let script = try embedScriptGenerator.script(
                sourceRootPath: sourceRootPath,
                frameworkReferences: frameworkReferences,
                includeSymbolsInFileLists: !target.product.testsBundle
            )

            precompiledEmbedPhase.shellScript = script.script
            precompiledEmbedPhase.inputPaths = script.inputPaths
                .map { "$(SRCROOT)/\($0.pathString)" }
            precompiledEmbedPhase.outputPaths = script.outputPaths

            pbxproj.add(object: precompiledEmbedPhase)
            pbxTarget.buildPhases.append(precompiledEmbedPhase)
        }

        pbxproj.add(object: embedPhase)
        pbxTarget.buildPhases.append(embedPhase)
    }

    func setupFrameworkSearchPath(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let linkableModules = try graphTraverser.searchablePathDependencies(path: path, name: target.name).sorted()

        let precompiledPaths = linkableModules.compactMap(\.precompiledPath)
            .map { LinkGeneratorPath.absolutePath($0.removingLastComponent()) }
        let sdkPaths = linkableModules.compactMap { (dependency: GraphDependencyReference) -> LinkGeneratorPath? in
            if case let GraphDependencyReference.sdk(_, _, source) = dependency {
                return source.frameworkSearchPath.map { LinkGeneratorPath.string($0) }
            } else {
                return nil
            }
        }

        let uniquePaths = Array(Set(precompiledPaths + sdkPaths))
        try setup(
            setting: "FRAMEWORK_SEARCH_PATHS",
            paths: uniquePaths,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath
        )
    }

    func setupHeadersSearchPath(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let headersSearchPaths = graphTraverser.librariesPublicHeadersFolders(path: path, name: target.name).sorted()
        try setup(
            setting: "HEADER_SEARCH_PATHS",
            paths: headersSearchPaths.map(LinkGeneratorPath.absolutePath),
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath
        )
    }

    func setupLibrarySearchPaths(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let librarySearchPaths = try graphTraverser.librariesSearchPaths(path: path, name: target.name).sorted()
        try setup(
            setting: "LIBRARY_SEARCH_PATHS",
            paths: librarySearchPaths.map(LinkGeneratorPath.absolutePath),
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath
        )
    }

    func setupSwiftIncludePaths(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let swiftIncludePaths = graphTraverser.librariesSwiftIncludePaths(path: path, name: target.name).sorted()
        try setup(
            setting: "SWIFT_INCLUDE_PATHS",
            paths: swiftIncludePaths.map(LinkGeneratorPath.absolutePath),
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath
        )
    }

    func setupRunPathSearchPaths(
        target: Target,
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let runPathSearchPaths = graphTraverser.runPathSearchPaths(path: path, name: target.name).sorted()
        try setup(
            setting: "LD_RUNPATH_SEARCH_PATHS",
            paths: runPathSearchPaths.map(LinkGeneratorPath.absolutePath),
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath
        )
    }

    private func setup(
        setting name: String,
        paths: [LinkGeneratorPath],
        pbxTarget: PBXTarget,
        sourceRootPath: AbsolutePath
    ) throws {
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

    func generateLinkingPhase(
        target: Target,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements,
        path: AbsolutePath,
        graphTraverser: GraphTraversing
    ) throws {
        let linkableDependencies = try graphTraverser.linkableDependencies(path: path, name: target.name).sorted()

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

        try linkableDependencies
            .forEach { dependency in
                switch dependency {
                case let .framework(path, _, _, _, _, _, _, _):
                    try addBuildFile(path)
                case let .library(path, _, _, _):
                    try addBuildFile(path)
                case let .xcframework(path, _, _, _):
                    try addBuildFile(path)
                case .bundle:
                    break
                case let .product(target, _, platformFilter):
                    guard let fileRef = fileElements.product(target: target) else {
                        throw LinkGeneratorError.missingProduct(name: target)
                    }
                    let buildFile = PBXBuildFile(file: fileRef)
                    buildFile.platformFilter = platformFilter?.xcodeprojValue
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

    func generateCopyProductsBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) throws {
        let dependencies = graphTraverser.copyProductDependencies(path: path, name: target.name).sorted()

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
        try generateDependenciesBuildPhase(
            dependencies: dependencies,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements
        )

        // For static framewor/library XCFrameworks, we need Xcode to process it to extract the
        // the relevant product within it within it based on the architecture and place in
        // the products directory. This allows the current target to see the symbols from the XCFramework.
        //
        // Copying to products is not a nop like it is for regular static targets due to the processing step,
        // applying the same technique results in the following error:
        //
        // ```
        // Multiple commands produce  ...
        // ```
        // A slightly different build phase is needed, where the destination is unique per target (this does
        // lead to some wasted derrived data disk space, but only when archiving to limit impact).
        // As of Xcode 14.2, this seems to achieve the desired effect of getting Xcode to process the XCFramework
        // without explicitly linking it nor producing the multiple commands error.
        try generateStaticXCFrameworksDependenciesBuildPhase(
            dependencies: dependencies,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            target: target,
            fileElements: fileElements
        )
    }

    private func generateDependenciesBuildPhase(
        dependencies: [GraphDependencyReference],
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        fileElements: ProjectFileElements
    ) throws {
        var files: [PBXBuildFile] = []

        for dependency in dependencies.sorted() {
            switch dependency {
            case let .product(target: target, _, platformFilter: platformFilter):
                guard let fileRef = fileElements.product(target: target) else {
                    throw LinkGeneratorError.missingProduct(name: target)
                }

                let buildFile = PBXBuildFile(file: fileRef)
                buildFile.platformFilter = platformFilter?.xcodeprojValue
                pbxproj.add(object: buildFile)
                files.append(buildFile)
            case let .framework(path: path, _, _, _, _, _, _, _),
                 let .library(path: path, _, _, _):
                guard let fileRef = fileElements.file(path: path) else {
                    throw LinkGeneratorError.missingReference(path: path)
                }
                let buildFile = PBXBuildFile(file: fileRef)
                pbxproj.add(object: buildFile)
                files.append(buildFile)
            default:
                break
            }
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

    private func generateStaticXCFrameworksDependenciesBuildPhase(
        dependencies: [GraphDependencyReference],
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        target: Target,
        fileElements: ProjectFileElements
    ) throws {
        var files: [PBXBuildFile] = []

        for dependency in dependencies.sorted() {
            switch dependency {
            case let .xcframework(path: path, _, _, _):
                guard let fileRef = fileElements.file(path: path) else {
                    throw LinkGeneratorError.missingReference(path: path)
                }
                let buildFile = PBXBuildFile(file: fileRef)
                pbxproj.add(object: buildFile)
                files.append(buildFile)
            default:
                break
            }
        }

        if files.isEmpty {
            return
        }

        // Need a unique (but stable) destination path per target
        // to avoid "multiple commands produce:" errors in Xcode
        let buildPhase = PBXCopyFilesBuildPhase(
            dstPath: "_StaticXCFrameworkDependencies/\(target.name)",
            dstSubfolderSpec: .productsDirectory,
            name: "Static XCFramework Dependencies",
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
        return PBXBuildFile(
            file: fileReference,
            settings: settings
        )
    }
}

extension XCBuildConfiguration {
    fileprivate func append(setting name: String, value: String) {
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
