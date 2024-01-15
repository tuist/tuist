import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

enum BuildPhaseGenerationError: FatalError, Equatable {
    case missingFileReference(AbsolutePath)

    var description: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path.pathString) to a build phase that hasn't been added to the project."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingFileReference:
            return .bug
        }
    }
}

protocol BuildPhaseGenerating: AnyObject {
    func generateBuildPhases(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws

    /// Generates target actions
    ///
    /// - Parameters:
    ///   - scripts: Scripts to be generated as script build phases.
    ///   - pbxTarget: PBXTarget from the Xcode project.
    ///   - pbxproj: PBXProj instance.
    ///   - sourceRootPath: Path to the directory that will contain the generated project.
    /// - Throws: An error if the script phase can't be generated.
    func generateScripts(
        _ scripts: [TargetScript],
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        sourceRootPath: AbsolutePath
    ) throws
}

// swiftlint:disable:next type_body_length
final class BuildPhaseGenerator: BuildPhaseGenerating {
    // MARK: - Attributes

    // swiftlint:disable:next function_body_length
    func generateBuildPhases(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        if target.shouldIncludeHeadersBuildPhase, let headers = target.headers {
            try generateHeadersBuildPhase(
                headers: headers,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }

        if target.supportsSources {
            try generateSourcesBuildPhase(
                files: target.sources,
                coreDataModels: target.coreDataModels,
                target: target,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }

        try generateResourcesBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        try generateCopyFilesBuildPhases(
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        try generateAppExtensionsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        try generateExtensionKitExtensionsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        if target.canEmbedWatchApplications() {
            try generateEmbedWatchBuildPhase(
                path: path,
                target: target,
                graphTraverser: graphTraverser,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }

        try generateEmbedXPCServicesBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        if target.canEmbedSystemExtensions() {
            try generateEmbedSystemExtensionBuildPhase(
                path: path,
                target: target,
                graphTraverser: graphTraverser,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }

        generateRawScriptBuildPhases(
            target.rawScriptBuildPhases,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj
        )

        try generateEmbedAppClipsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )
    }

    func generateScripts(
        _ scripts: [TargetScript],
        pbxTarget: PBXTarget,
        pbxproj: PBXProj,
        sourceRootPath: AbsolutePath
    ) throws {
        for script in scripts {
            let buildPhase = try PBXShellScriptBuildPhase(
                files: [],
                name: script.name,
                inputPaths: script.inputPaths
                    .map {
                        (try? AbsolutePath(validating: $0))?.relative(to: sourceRootPath).pathString ?? $0
                    },
                outputPaths: script.outputPaths
                    .map {
                        (try? AbsolutePath(validating: $0))?.relative(to: sourceRootPath).pathString ?? $0
                    },
                inputFileListPaths: script.inputFileListPaths.map { $0.relative(to: sourceRootPath).pathString },

                outputFileListPaths: script.outputFileListPaths.map { $0.relative(to: sourceRootPath).pathString },

                shellPath: script.shellPath,
                shellScript: script.shellScript(sourceRootPath: sourceRootPath),
                runOnlyForDeploymentPostprocessing: script.runForInstallBuildsOnly,
                showEnvVarsInLog: script.showEnvVarsInLog,
                dependencyFile: script.dependencyFile?.relative(to: sourceRootPath).pathString
            )
            if let basedOnDependencyAnalysis = script.basedOnDependencyAnalysis {
                // Force the script to run in all incremental builds, if we
                // are NOT running it based on dependency analysis. Otherwise
                // leave it at the default value.
                buildPhase.alwaysOutOfDate = !basedOnDependencyAnalysis
            }

            pbxproj.add(object: buildPhase)
            pbxTarget.buildPhases.append(buildPhase)
        }
    }

    func generateRawScriptBuildPhases(
        _ rawScriptBuildPhases: [RawScriptBuildPhase],
        pbxTarget: PBXTarget,
        pbxproj: PBXProj
    ) {
        for script in rawScriptBuildPhases {
            let buildPhase = PBXShellScriptBuildPhase(
                files: [],
                name: script.name,
                shellPath: script.shellPath,
                shellScript: script.script,
                showEnvVarsInLog: script.showEnvVarsInLog
            )
            pbxproj.add(object: buildPhase)
            pbxTarget.buildPhases.append(buildPhase)
        }
    }

    // swiftlint:disable:next function_body_length
    func generateSourcesBuildPhase(
        files: [SourceFile],
        coreDataModels: [CoreDataModel],
        target: Target,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        pbxproj.add(object: sourcesBuildPhase)
        pbxTarget.buildPhases.append(sourcesBuildPhase)

        var buildFilesCache = Set<AbsolutePath>()
        let sortedFiles = files
            .sorted(by: { $0.path < $1.path })

        var pbxBuildFiles = [PBXBuildFile]()
        for buildFile in sortedFiles {
            let buildFilePath = buildFile.path
            let isLocalized = buildFilePath.pathString.contains(".lproj/")
            let element: (element: PBXFileElement, path: AbsolutePath)
            if !isLocalized {
                guard let fileReference = fileElements.file(path: buildFile.path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFile.path)
                }
                element = (fileReference, buildFilePath)
            } else {
                let name = buildFilePath.basename
                let path = buildFilePath.parentDirectory.parentDirectory.appending(component: name)
                guard let group = fileElements.group(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (group, path)
            }

            var settings: [String: Any]?
            if let compilerFlags = buildFile.compilerFlags {
                settings = [
                    "COMPILER_FLAGS": compilerFlags,
                ]
            }

            /// Source file ATTRIBUTES
            /// example: `settings = {ATTRIBUTES = (codegen, )`}
            if let codegen = buildFile.codeGen {
                var settingsCopy = settings ?? [:]
                var attributes = settingsCopy["ATTRIBUTES"] as? [String] ?? []
                attributes.append(codegen.rawValue)
                settingsCopy["ATTRIBUTES"] = attributes
                settings = settingsCopy
            }

            if buildFilesCache.contains(element.path) == false {
                let pbxBuildFile = PBXBuildFile(file: element.element, settings: settings)
                pbxBuildFile.applyCondition(buildFile.compilationCondition, applicableTo: target)
                pbxBuildFiles.append(pbxBuildFile)
                buildFilesCache.insert(element.path)
            }
        }

        pbxBuildFiles.append(contentsOf: generateCoreDataModels(
            coreDataModels: coreDataModels,
            fileElements: fileElements,
            pbxproj: pbxproj
        ))
        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        sourcesBuildPhase.files = pbxBuildFiles
    }

    func generateHeadersBuildPhase(
        headers: Headers,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let headersBuildPhase = PBXHeadersBuildPhase()
        pbxproj.add(object: headersBuildPhase)
        pbxTarget.buildPhases.append(headersBuildPhase)

        let addHeader: (AbsolutePath, String?) throws -> PBXBuildFile = { path, accessLevel in
            guard let fileReference = fileElements.file(path: path) else {
                throw BuildPhaseGenerationError.missingFileReference(path)
            }
            let settings: [String: [String]]? = accessLevel.map {
                ["ATTRIBUTES": [$0.capitalized]]
            }
            return PBXBuildFile(file: fileReference, settings: settings)
        }
        let pbxBuildFiles = try headers.private.sorted().map { try addHeader($0, "private") } +
            headers.public.sorted().map { try addHeader($0, "public") } +
            headers.project.sorted().map { try addHeader($0, nil) }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        headersBuildPhase.files = pbxBuildFiles
    }

    func generateResourcesBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        pbxproj.add(object: resourcesBuildPhase)
        pbxTarget.buildPhases.append(resourcesBuildPhase)

        var pbxBuildFiles = [PBXBuildFile]()

        pbxBuildFiles.append(contentsOf: try generateResourcesBuildFile(
            target: target,
            files: target.resources,
            fileElements: fileElements
        ))

        try pbxBuildFiles.append(contentsOf: generateResourceBundle(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            fileElements: fileElements
        ))

        if !target.supportsSources {
            // CoreData models are typically added to the sources build phase
            // and Xcode automatically bundles the models.
            // For static libraries / frameworks however, they don't support resources,
            // the models could be bundled in a stand alone `.bundle`
            // as resources.
            //
            // e.g.
            // MyStaticFramework (.staticFramework) -> Includes CoreData models as sources
            // MyStaticFrameworkResources (.bundle) -> Includes CoreData models as resources
            //
            // - Note: Technically, CoreData models can be added a sources build phase in a `.bundle`
            // but that will result in the `.bundle` having an executable, which is not valid on iOS.
            pbxBuildFiles.append(contentsOf: generateCoreDataModels(
                coreDataModels: target.coreDataModels,
                fileElements: fileElements,
                pbxproj: pbxproj
            ))
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        resourcesBuildPhase.files = pbxBuildFiles
    }

    func generateCopyFilesBuildPhases(
        target: Target,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        for action in target.copyFiles {
            let copyFilesPhase = PBXCopyFilesBuildPhase(
                dstPath: action.subpath,
                dstSubfolderSpec: action.destination.toXcodeprojSubFolder,
                name: action.name
            )

            pbxproj.add(object: copyFilesPhase)
            pbxTarget.buildPhases.append(copyFilesPhase)

            var buildFilesCache = Set<AbsolutePath>()
            let filePaths = action.files.map(\.path).sorted()

            var pbxBuildFiles = [PBXBuildFile]()
            for filePath in filePaths {
                guard let fileReference = fileElements.file(path: filePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(filePath)
                }

                if buildFilesCache.contains(filePath) == false {
                    let pbxBuildFile = PBXBuildFile(file: fileReference)
                    pbxBuildFiles.append(pbxBuildFile)
                    buildFilesCache.insert(filePath)
                }
            }
            pbxBuildFiles.forEach { pbxproj.add(object: $0) }
            copyFilesPhase.files = pbxBuildFiles
        }
    }

    private func generateResourcesBuildFile(
        target: Target,
        files: [ResourceFileElement],
        fileElements: ProjectFileElements
    ) throws -> [PBXBuildFile] {
        var buildFilesCache = Set<AbsolutePath>()
        var pbxBuildFiles = [PBXBuildFile]()
        let ignoredVariantGroupExtensions = [".intentdefinition"]

        for resource in files.sorted(by: { $0.path < $1.path }) {
            let buildFilePath = resource.path

            let pathString = buildFilePath.pathString
            let isLocalized = pathString.contains(".lproj/")
            let isLproj = buildFilePath.extension == "lproj"

            var element: (element: PBXFileElement, path: AbsolutePath)?

            if isLocalized {
                guard let (group, path) = fileElements.variantGroup(containing: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }

                // Xcode automatically copies the string files for some files (i.e. .intentdefinition files), hence we need
                // to remove them from the Copy Resources build phase
                if let suffix = path.suffix, ignoredVariantGroupExtensions.contains(suffix) {
                    continue
                }

                element = (group, path)
            } else if !isLproj {
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (fileReference, buildFilePath)
            }
            if let element, buildFilesCache.contains(element.path) == false {
                let tags = resource.tags.sorted()
                let settings: [String: Any]? = !tags.isEmpty ? ["ASSET_TAGS": tags] : nil

                let pbxBuildFile = PBXBuildFile(file: element.element, settings: settings)
                pbxBuildFile.applyCondition(resource.inclusionCondition, applicableTo: target)
                pbxBuildFiles.append(pbxBuildFile)
                buildFilesCache.insert(element.path)
            }
        }
        return pbxBuildFiles
    }

    private func generateCoreDataModels(
        coreDataModels: [CoreDataModel],
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) -> [PBXBuildFile] {
        let coreDataModels = coreDataModels.sorted { $0.path < $1.path }
        return coreDataModels.map {
            self.generateCoreDataModel(
                coreDataModel: $0,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }
    }

    private func generateCoreDataModel(
        coreDataModel: CoreDataModel,
        fileElements: ProjectFileElements,
        pbxproj _: PBXProj
    ) -> PBXBuildFile {
        let currentVersion = coreDataModel.currentVersion
        let path = coreDataModel.path
        let currentVersionPath = path.appending(component: "\(currentVersion).xcdatamodel")
        // swiftlint:disable:next force_cast
        let modelReference = fileElements.group(path: path)! as! XCVersionGroup
        let currentVersionReference = fileElements.file(path: currentVersionPath)!
        modelReference.currentVersion = currentVersionReference

        let pbxBuildFile = PBXBuildFile(file: modelReference)
        return pbxBuildFile
    }

    private func generateResourceBundle(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        fileElements: ProjectFileElements
    ) throws -> [PBXBuildFile] {
        let bundles = graphTraverser
            .resourceBundleDependencies(path: path, name: target.name)
            .sorted()
        let buildFiles = bundles.compactMap { dependency -> PBXBuildFile? in
            switch dependency {
            case let .bundle(path: path, condition: condition):
                let buildFile = PBXBuildFile(file: fileElements.file(path: path))
                buildFile.applyCondition(condition, applicableTo: target)
                return buildFile
            case let .product(target: targetName, _, condition: condition):
                let buildFile = PBXBuildFile(file: fileElements.product(target: targetName))
                buildFile.applyCondition(condition, applicableTo: target)
                return buildFile
            default:
                return nil
            }
        }

        return buildFiles
    }

    func generateAppExtensionsBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let appExtensions = graphTraverser.appExtensionDependenciesWithConditions(path: path, name: target.name)
            .sorted { lhsTarget, rhsTarget in
                lhsTarget.0 < rhsTarget.0
            }
        guard !appExtensions.isEmpty else { return }

        let appExtensionsBuildPhase = PBXCopyFilesBuildPhase(dstSubfolderSpec: .plugins, name: "Embed Foundation Extensions")
        pbxproj.add(object: appExtensionsBuildPhase)
        pbxTarget.buildPhases.append(appExtensionsBuildPhase)

        let pbxBuildFiles: [PBXBuildFile] = appExtensions.compactMap { graphTarget, condition in
            guard let fileReference = fileElements.product(target: graphTarget.target.name) else { return nil }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            pbxBuildFile.applyCondition(condition, applicableTo: target)
            return pbxBuildFile
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        appExtensionsBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedWatchBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let targetDependencies = graphTraverser.directLocalTargetDependenciesWithConditions(path: path, name: target.name)
            .sorted { lhsTarget, rhsTarget in
                lhsTarget.0 < rhsTarget.0
            }
        let watchApps = targetDependencies.filter { $0.0.target.isEmbeddableWatchApplication() }
        guard !watchApps.isEmpty else { return }

        let embedWatchAppBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(CONTENTS_FOLDER_PATH)/Watch",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed Watch Content"
        )
        pbxproj.add(object: embedWatchAppBuildPhase)
        pbxTarget.buildPhases.append(embedWatchAppBuildPhase)

        let pbxBuildFiles: [PBXBuildFile] = watchApps.compactMap { graphTarget, condition in
            guard let fileReference = fileElements.product(target: graphTarget.target.name) else { return nil }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            pbxBuildFile.applyCondition(condition, applicableTo: target)
            return pbxBuildFile
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedWatchAppBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedAppClipsBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        guard target.product == .app else {
            return
        }

        guard let (appClip, condition) = graphTraverser.appClipDependenciesWithConditions(path: path, name: target.name) else {
            return
        }
        var pbxBuildFiles = [PBXBuildFile]()

        let embedAppClipsBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(CONTENTS_FOLDER_PATH)/AppClips",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed App Clips"
        )
        pbxproj.add(object: embedAppClipsBuildPhase)
        pbxTarget.buildPhases.append(embedAppClipsBuildPhase)

        let refs = fileElements.product(target: appClip.target.name)

        let pbxBuildFile = PBXBuildFile(file: refs, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
        pbxBuildFile.applyCondition(condition, applicableTo: target)
        pbxBuildFiles.append(pbxBuildFile)
        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedAppClipsBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedXPCServicesBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: path, name: target.name).sorted()
        let xpcServices = targetDependencies.filter { $0.target.isEmbeddableXPCService() }
        guard !xpcServices.isEmpty else { return }

        let embedXPCServicesBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(CONTENTS_FOLDER_PATH)/XPCServices",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed XPC Services"
        )
        pbxproj.add(object: embedXPCServicesBuildPhase)
        pbxTarget.buildPhases.append(embedXPCServicesBuildPhase)

        let pbxBuildFiles: [PBXBuildFile] = xpcServices.compactMap { graphTarget in
            guard let fileReference = fileElements.product(target: graphTarget.target.name) else { return nil }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            if !graphTarget.target.isExclusiveTo(.macOS) {
                pbxBuildFile.applyPlatformFilters([.macos])
            }
            return pbxBuildFile
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedXPCServicesBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedSystemExtensionBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: path, name: target.name).sorted()
        let systemExtensions = targetDependencies.filter { $0.target.isEmbeddableSystemExtension() }
        guard !systemExtensions.isEmpty else { return }

        let embedSystemExtensionsBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(CONTENTS_FOLDER_PATH)/Library/SystemExtensions",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed System Extensions"
        )
        pbxproj.add(object: embedSystemExtensionsBuildPhase)
        pbxTarget.buildPhases.append(embedSystemExtensionsBuildPhase)

        let pbxBuildFiles: [PBXBuildFile] = systemExtensions.compactMap { graphTarget in
            guard let fileReference = fileElements.product(target: graphTarget.target.name) else { return nil }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            if !graphTarget.target.isExclusiveTo(.macOS) {
                pbxBuildFile.applyPlatformFilters([.macos])
            }
            return pbxBuildFile
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedSystemExtensionsBuildPhase.files = pbxBuildFiles
    }

    func generateExtensionKitExtensionsBuildPhase(
        path: AbsolutePath,
        target: Target,
        graphTraverser: GraphTraversing,
        pbxTarget: PBXTarget,
        fileElements: ProjectFileElements,
        pbxproj: PBXProj
    ) throws {
        let extensions = graphTraverser.extensionKitExtensionDependenciesWithConditions(path: path, name: target.name)
            .sorted { lhsTarget, rhsTarget in
                lhsTarget.0 < rhsTarget.0
            }
        guard !extensions.isEmpty else { return }

        let extensionKitExtensionsBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(EXTENSIONS_FOLDER_PATH)",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed ExtensionKit Extensions"
        )
        pbxproj.add(object: extensionKitExtensionsBuildPhase)
        pbxTarget.buildPhases.append(extensionKitExtensionsBuildPhase)

        let pbxBuildFiles: [PBXBuildFile] = extensions.compactMap { graphTarget, condition in
            guard let fileReference = fileElements.product(target: graphTarget.target.name) else { return nil }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            pbxBuildFile.applyCondition(condition, applicableTo: target)
            return pbxBuildFile
        }

        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        extensionKitExtensionsBuildPhase.files = pbxBuildFiles
    }
}
