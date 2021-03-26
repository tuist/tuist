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

    static func == (lhs: BuildPhaseGenerationError, rhs: BuildPhaseGenerationError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFileReference(lhsPath), .missingFileReference(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

protocol BuildPhaseGenerating: AnyObject {
    func generateBuildPhases(path: AbsolutePath,
                             target: Target,
                             graphTraverser: GraphTraversing,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj) throws

    /// Generates target actions
    ///
    /// - Parameters:
    ///   - actions: Actions to be generated as script build phases.
    ///   - pbxTarget: PBXTarget from the Xcode project.
    ///   - pbxproj: PBXProj instance.
    ///   - sourceRootPath: Path to the directory that will contain the generated project.
    /// - Throws: An error if the script phase can't be generated.
    func generateActions(actions: [TargetAction],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) throws
}

// swiftlint:disable:next type_body_length
final class BuildPhaseGenerator: BuildPhaseGenerating {
    // MARK: - Attributes

    // swiftlint:disable:next function_body_length
    func generateBuildPhases(path: AbsolutePath,
                             target: Target,
                             graphTraverser: GraphTraversing,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj) throws
    {
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

        try generateEmbedWatchBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        generateScripts(
            target.scripts,
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

    func generateActions(actions: [TargetAction],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) throws
    {
        try actions.forEach { action in
            let buildPhase = try PBXShellScriptBuildPhase(
                files: [],
                name: action.name,
                inputPaths: action.inputPaths.map { $0.relative(to: sourceRootPath).pathString },
                outputPaths: action.outputPaths.map { $0.relative(to: sourceRootPath).pathString },
                inputFileListPaths: action.inputFileListPaths.map { $0.relative(to: sourceRootPath).pathString }, // swiftlint:disable:this line_length

                outputFileListPaths: action.outputFileListPaths.map { $0.relative(to: sourceRootPath).pathString }, // swiftlint:disable:this line_length

                shellPath: "/bin/sh",
                shellScript: action.shellScript(sourceRootPath: sourceRootPath),
                showEnvVarsInLog: action.showEnvVarsInLog
            )
            if let basedOnDependencyAnalysis = action.basedOnDependencyAnalysis {
                // Force the script to run in all incremental builds, if we
                // are NOT running it based on dependency analysis. Otherwise
                // leave it at the default value.
                buildPhase.alwaysOutOfDate = !basedOnDependencyAnalysis
            }

            pbxproj.add(object: buildPhase)
            pbxTarget.buildPhases.append(buildPhase)
        }
    }

    func generateScripts(_ scripts: [TargetScript],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj)
    {
        scripts.forEach { script in
            let buildPhase = PBXShellScriptBuildPhase(
                files: [],
                name: script.name,
                shellPath: "/bin/sh",
                shellScript: script.script,
                showEnvVarsInLog: script.showEnvVarsInLog
            )
            pbxproj.add(object: buildPhase)
            pbxTarget.buildPhases.append(buildPhase)
        }
    }

    func generateSourcesBuildPhase(files: [SourceFile],
                                   coreDataModels: [CoreDataModel],
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   pbxproj: PBXProj) throws
    {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        pbxproj.add(object: sourcesBuildPhase)
        pbxTarget.buildPhases.append(sourcesBuildPhase)

        var buildFilesCache = Set<AbsolutePath>()
        let sortedFiles = files.sorted(by: { $0.path < $1.path })
        var pbxBuildFiles = [PBXBuildFile]()
        try sortedFiles.forEach { buildFile in
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

            if buildFilesCache.contains(element.path) == false {
                let pbxBuildFile = PBXBuildFile(file: element.element, settings: settings)
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

    func generateHeadersBuildPhase(headers: Headers,
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   pbxproj: PBXProj) throws
    {
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

    func generateResourcesBuildPhase(path: AbsolutePath,
                                     target: Target,
                                     graphTraverser: GraphTraversing,
                                     pbxTarget: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     pbxproj: PBXProj) throws
    {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        pbxproj.add(object: resourcesBuildPhase)
        pbxTarget.buildPhases.append(resourcesBuildPhase)

        var pbxBuildFiles = [PBXBuildFile]()

        pbxBuildFiles.append(contentsOf: try generateResourcesBuildFile(
            files: target.resources,
            fileElements: fileElements,
            pbxproj: pbxproj
        ))

        pbxBuildFiles.append(contentsOf: generateResourceBundle(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            fileElements: fileElements,
            pbxproj: pbxproj
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

    func generateCopyFilesBuildPhases(target: Target,
                                      pbxTarget: PBXTarget,
                                      fileElements: ProjectFileElements,
                                      pbxproj: PBXProj) throws
    {
        try target.copyFiles.forEach { action in
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
            try filePaths.forEach {
                guard let fileReference = fileElements.file(path: $0) else {
                    throw BuildPhaseGenerationError.missingFileReference($0)
                }

                if buildFilesCache.contains($0) == false {
                    let pbxBuildFile = PBXBuildFile(file: fileReference)
                    pbxBuildFiles.append(pbxBuildFile)
                    buildFilesCache.insert($0)
                }
            }
            pbxBuildFiles.forEach { pbxproj.add(object: $0) }
            copyFilesPhase.files = pbxBuildFiles
        }
    }

    private func generateResourcesBuildFile(files: [ResourceFileElement],
                                            fileElements: ProjectFileElements,
                                            pbxproj _: PBXProj) throws
        -> [PBXBuildFile]
    {
        var buildFilesCache = Set<AbsolutePath>()
        var pbxBuildFiles = [PBXBuildFile]()

        try files.sorted(by: { $0.path < $1.path }).forEach { resource in
            let buildFilePath = resource.path

            let pathString = buildFilePath.pathString
            let isLocalized = pathString.contains(".lproj/")
            let isLproj = buildFilePath.extension == "lproj"
            let isWithinAssets = pathString.contains(".xcassets/") || pathString.contains(".scnassets/")

            /// Assets that are part of a .xcassets or .scnassets folder
            /// are not added individually. The whole folder is added
            /// instead as a group.
            if isWithinAssets {
                return
            }

            var element: (element: PBXFileElement, path: AbsolutePath)?

            if isLocalized {
                let name = buildFilePath.basename
                let path = buildFilePath.parentDirectory.parentDirectory.appending(component: name)
                guard let group = fileElements.group(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (group, path)
            } else if !isLproj {
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (fileReference, buildFilePath)
            }
            if let element = element, buildFilesCache.contains(element.path) == false {
                let tags = resource.tags.sorted()
                let settings: [String: Any]? = !tags.isEmpty ? ["ASSET_TAGS": tags] : nil

                let pbxBuildFile = PBXBuildFile(file: element.element, settings: settings)
                pbxBuildFiles.append(pbxBuildFile)
                buildFilesCache.insert(element.path)
            }
        }
        return pbxBuildFiles
    }

    private func generateCoreDataModels(coreDataModels: [CoreDataModel],
                                        fileElements: ProjectFileElements,
                                        pbxproj: PBXProj) -> [PBXBuildFile]
    {
        let coreDataModels = coreDataModels.sorted { $0.path < $1.path }
        return coreDataModels.map {
            self.generateCoreDataModel(
                coreDataModel: $0,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        }
    }

    private func generateCoreDataModel(coreDataModel: CoreDataModel,
                                       fileElements: ProjectFileElements,
                                       pbxproj _: PBXProj) -> PBXBuildFile
    {
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

    private func generateResourceBundle(path: AbsolutePath,
                                        target: Target,
                                        graphTraverser: GraphTraversing,
                                        fileElements: ProjectFileElements,
                                        pbxproj _: PBXProj) -> [PBXBuildFile]
    {
        var pbxBuildFiles = [PBXBuildFile]()
        let bundles = graphTraverser
            .resourceBundleDependencies(path: path, name: target.name)
            .sorted()
        let refs = bundles.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0)
            pbxBuildFiles.append(pbxBuildFile)
        }
        return pbxBuildFiles
    }

    func generateAppExtensionsBuildPhase(path: AbsolutePath,
                                         target: Target,
                                         graphTraverser: GraphTraversing,
                                         pbxTarget: PBXTarget,
                                         fileElements: ProjectFileElements,
                                         pbxproj: PBXProj) throws
    {
        let appExtensions = graphTraverser.appExtensionDependencies(path: path, name: target.name).sorted()
        guard !appExtensions.isEmpty else { return }
        var pbxBuildFiles = [PBXBuildFile]()

        let appExtensionsBuildPhase = PBXCopyFilesBuildPhase(dstSubfolderSpec: .plugins, name: "Embed App Extensions")
        pbxproj.add(object: appExtensionsBuildPhase)
        pbxTarget.buildPhases.append(appExtensionsBuildPhase)

        let refs = appExtensions.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            pbxBuildFiles.append(pbxBuildFile)
        }
        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        appExtensionsBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedWatchBuildPhase(path: AbsolutePath,
                                      target: Target,
                                      graphTraverser: GraphTraversing,
                                      pbxTarget: PBXTarget,
                                      fileElements: ProjectFileElements,
                                      pbxproj: PBXProj) throws
    {
        let targetDependencies = graphTraverser.directLocalTargetDependencies(path: path, name: target.name).sorted()
        let watchApps = targetDependencies.filter { $0.target.product == .watch2App }
        guard !watchApps.isEmpty else { return }
        var pbxBuildFiles = [PBXBuildFile]()

        let embedWatchAppBuildPhase = PBXCopyFilesBuildPhase(
            dstPath: "$(CONTENTS_FOLDER_PATH)/Watch",
            dstSubfolderSpec: .productsDirectory,
            name: "Embed Watch Content"
        )
        pbxproj.add(object: embedWatchAppBuildPhase)
        pbxTarget.buildPhases.append(embedWatchAppBuildPhase)

        let refs = watchApps.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
            pbxBuildFiles.append(pbxBuildFile)
        }
        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedWatchAppBuildPhase.files = pbxBuildFiles
    }

    func generateEmbedAppClipsBuildPhase(path: AbsolutePath,
                                         target: Target,
                                         graphTraverser: GraphTraversing,
                                         pbxTarget: PBXTarget,
                                         fileElements: ProjectFileElements,
                                         pbxproj: PBXProj) throws
    {
        guard target.product == .app else {
            return
        }

        guard let appClips = graphTraverser.appClipDependencies(path: path, name: target.name) else {
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

        let refs = fileElements.product(target: appClips.target.name)

        let pbxBuildFile = PBXBuildFile(file: refs, settings: ["ATTRIBUTES": ["RemoveHeadersOnCopy"]])
        pbxBuildFiles.append(pbxBuildFile)
        pbxBuildFiles.forEach { pbxproj.add(object: $0) }
        embedAppClipsBuildPhase.files = pbxBuildFiles
    }
}
