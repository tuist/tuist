import Basic
import Foundation
import PathKit
import TuistCore
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
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graphing) throws
}

// swiftlint:disable type_body_length
final class LinkGenerator: LinkGenerating {
    /// An instance to locate tuist binaries.
    let binaryLocator: BinaryLocating

    /// Initializes the link generator with its attributes.
    ///
    /// - Parameter binaryLocator: An instance to locate tuist binaries.
    init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    // MARK: - LinkGenerating

    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       pbxproj: PBXProj,
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graphing) throws {
        let embeddableFrameworks = try graph.embeddableFrameworks(path: path, name: target.name)
        let linkableModules = try graph.linkableDependencies(path: path, name: target.name)
        let packages = try graph.packages(path: path, name: target.name)

        try setupSearchAndIncludePaths(target: target,
                                       pbxTarget: pbxTarget,
                                       sourceRootPath: sourceRootPath,
                                       path: path,
                                       graph: graph,
                                       linkableModules: linkableModules)

        try generateEmbedPhase(dependencies: embeddableFrameworks,
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
                             pbxProject: pbxProject,
                             packages: packages)
    }

    private func setupSearchAndIncludePaths(target: Target,
                                            pbxTarget: PBXTarget,
                                            sourceRootPath: AbsolutePath,
                                            path: AbsolutePath,
                                            graph: Graphing,
                                            linkableModules: [DependencyReference]) throws {
        let headersSearchPaths = graph.librariesPublicHeadersFolders(path: path, name: target.name)
        let librarySearchPaths = graph.librariesSearchPaths(path: path, name: target.name)
        let swiftIncludePaths = graph.librariesSwiftIncludePaths(path: path, name: target.name)

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
    }

    func generatePackages(target _: Target,
                          pbxTarget: PBXTarget,
                          pbxProject: PBXProject,
                          packages: [PackageNode]) throws {
        try packages.forEach { package in
            switch package.packageType {
            case let .local(path: packagePath, productName: productName):
                _ = try pbxProject.addLocalSwiftPackage(path: Path(packagePath.pathString),
                                                        productName: productName,
                                                        targetName: pbxTarget.name,
                                                        addFileReference: false)
            case let .remote(url: url, productName: productName, versionRequirement: versionRequirement):
                _ = try pbxProject.addSwiftPackage(repositoryURL: url,
                                                   productName: productName,
                                                   versionRequirement: versionRequirement.xcodeprojValue,
                                                   targetName: pbxTarget.name)
            }
        }
    }

    func generateEmbedPhase(dependencies: [DependencyReference],
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

        var script: [String] = []

        try dependencies.forEach { dependency in
            if case let DependencyReference.absolute(path) = dependency {
                let relativePath = "$(SRCROOT)/\(path.relative(to: sourceRootPath).pathString)"
                let binary = binaryLocator.copyFrameworksBinary()
                script.append("\(binary) embed \(path.relative(to: sourceRootPath).pathString)")
                precompiledEmbedPhase.inputPaths.append(relativePath)
                precompiledEmbedPhase.outputPaths.append("$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/\(path.components.last!)")

            } else if case let DependencyReference.product(target, _) = dependency {
                guard let fileRef = fileElements.product(target: target) else {
                    throw LinkGeneratorError.missingProduct(name: target)
                }
                let buildFile = PBXBuildFile(file: fileRef, settings: ["ATTRIBUTES": ["CodeSignOnCopy"]])
                pbxproj.add(object: buildFile)
                embedPhase.files?.append(buildFile)
            }
        }
        if script.isEmpty {
            precompiledEmbedPhase.shellScript = "echo \"Skipping, nothing to be embedded.\""
        } else {
            precompiledEmbedPhase.shellScript = script.joined(separator: "\n")
        }
    }

    func setupFrameworkSearchPath(dependencies: [DependencyReference],
                                  pbxTarget: PBXTarget,
                                  sourceRootPath: AbsolutePath) throws {
        let paths = dependencies.compactMap { (dependency: DependencyReference) -> AbsolutePath? in
            if case let .absolute(path) = dependency { return path }
            return nil
        }
        .map { $0.removingLastComponent() }

        let uniquePaths = Array(Set(paths))
        try setup(setting: "FRAMEWORK_SEARCH_PATHS",
                  paths: uniquePaths,
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupHeadersSearchPath(_ paths: [AbsolutePath],
                                pbxTarget: PBXTarget,
                                sourceRootPath: AbsolutePath) throws {
        try setup(setting: "HEADER_SEARCH_PATHS",
                  paths: paths,
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupLibrarySearchPaths(_ paths: [AbsolutePath],
                                 pbxTarget: PBXTarget,
                                 sourceRootPath: AbsolutePath) throws {
        try setup(setting: "LIBRARY_SEARCH_PATHS",
                  paths: paths,
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    func setupSwiftIncludePaths(_ paths: [AbsolutePath],
                                pbxTarget: PBXTarget,
                                sourceRootPath: AbsolutePath) throws {
        try setup(setting: "SWIFT_INCLUDE_PATHS",
                  paths: paths,
                  pbxTarget: pbxTarget,
                  sourceRootPath: sourceRootPath)
    }

    private func setup(setting name: String,
                       paths: [AbsolutePath],
                       pbxTarget: PBXTarget,
                       sourceRootPath: AbsolutePath) throws {
        guard let configurationList = pbxTarget.buildConfigurationList else {
            throw LinkGeneratorError.missingConfigurationList(targetName: pbxTarget.name)
        }
        guard !paths.isEmpty else {
            return
        }
        let value = SettingValue
            .array(paths
                .map { $0.relative(to: sourceRootPath).pathString }
                .map { "$(SRCROOT)/\($0)" })
        let newSetting = [name: value]
        let inheritedSetting = [name: SettingValue.string("$(inherited)")]
        let helper = SettingsHelper()
        try configurationList.buildConfigurations.forEach { configuration in
            try helper.extend(buildSettings: &configuration.buildSettings, with: newSetting)
            try helper.extend(buildSettings: &configuration.buildSettings, with: inheritedSetting)
        }
    }

    func generateLinkingPhase(dependencies: [DependencyReference],
                              pbxTarget: PBXTarget,
                              pbxproj: PBXProj,
                              fileElements: ProjectFileElements) throws {
        let buildPhase = PBXFrameworksBuildPhase()
        pbxproj.add(object: buildPhase)
        pbxTarget.buildPhases.append(buildPhase)

        try dependencies
            .sorted()
            .forEach { dependency in
                switch dependency {
                case let .absolute(path):
                    guard let fileRef = fileElements.file(path: path) else {
                        throw LinkGeneratorError.missingReference(path: path)
                    }
                    let buildFile = PBXBuildFile(file: fileRef)
                    pbxproj.add(object: buildFile)
                    buildPhase.files?.append(buildFile)
                case let .product(target, _):
                    guard let fileRef = fileElements.product(target: target) else {
                        throw LinkGeneratorError.missingProduct(name: target)
                    }
                    let buildFile = PBXBuildFile(file: fileRef)
                    pbxproj.add(object: buildFile)
                    buildPhase.files?.append(buildFile)
                case let .sdk(sdkPath, sdkStatus):
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
                                         graph: Graphing,
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

    private func generateDependenciesBuildPhase(dependencies: [DependencyReference],
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
