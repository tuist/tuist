import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

public struct GroupFileElement: Hashable {
    var path: AbsolutePath
    var group: ProjectGroup
    var isReference: Bool

    init(path: AbsolutePath, group: ProjectGroup, isReference: Bool = false) {
        self.path = path
        self.group = group
        self.isReference = isReference
    }
}

// swiftlint:disable:next type_body_length
class ProjectFileElements {
    // MARK: - Static

    // swiftlint:disable:next force_try
    static let localizedRegex = try! NSRegularExpression(
        pattern: "(.+\\.lproj)/.+",
        options: []
    )

    private static let localizedGroupExtensions = [
        "storyboard",
        "strings",
        "xib",
        "intentdefinition",
    ]

    // MARK: - Attributes

    var elements: [AbsolutePath: PBXFileElement] = [:]
    var products: [String: PBXFileReference] = [:]
    var sdks: [AbsolutePath: PBXFileReference] = [:]
    var knownRegions: Set<String> = Set([])

    // MARK: - Init

    init(_ elements: [AbsolutePath: PBXFileElement] = [:]) {
        self.elements = elements
    }

    func generateProjectFiles(
        project: Project,
        graphTraverser: GraphTraversing,
        groups: ProjectGroups,
        pbxproj: PBXProj
    ) throws {
        var files = Set<GroupFileElement>()

        try project.targets.forEach { target in
            try files.formUnion(targetFiles(target: target))
        }
        let projectFileElements = projectFiles(project: project)
        files.formUnion(projectFileElements)

        let sortedFiles = files.sorted { one, two -> Bool in
            one.path < two.path
        }

        /// Files
        try generate(
            files: sortedFiles,
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: project.sourceRootPath
        )

        // Products
        let directProducts = project.targets.map {
            GraphDependencyReference.product(target: $0.name, productName: $0.productNameWithExtension)
        }

        // Dependencies
        let dependencies = try graphTraverser.allProjectDependencies(path: project.path).sorted()

        try generate(
            dependencyReferences: Set(directProducts + dependencies),
            groups: groups,
            pbxproj: pbxproj,
            sourceRootPath: project.sourceRootPath,
            filesGroup: project.filesGroup
        )
    }

    func projectFiles(project: Project) -> Set<GroupFileElement> {
        var fileElements = Set<GroupFileElement>()

        /// Config files
        let configFiles = project.settings.configurations.values.compactMap { $0?.xcconfig }

        fileElements.formUnion(configFiles.map {
            GroupFileElement(path: $0, group: project.filesGroup)
        })

        // Additional files
        fileElements.formUnion(project.additionalFiles.map {
            GroupFileElement(
                path: $0.path,
                group: project.filesGroup,
                isReference: $0.isReference
            )
        })

        // Add the .storekit files if needed. StoreKit files must be added to the
        // project/workspace so that the scheme can correctly reference them.
        // In case the configuration already contains such file, we should avoid adding it twice
        let storekitFiles = project.schemes.compactMap { scheme -> GroupFileElement? in
            guard let path = scheme.runAction?.options.storeKitConfigurationPath else { return nil }
            return GroupFileElement(path: path, group: project.filesGroup)
        }

        fileElements.formUnion(storekitFiles)

        // Add the .gpx files if needed. GPS Exchange files must be added to the
        // project/workspace so that the scheme can correctly reference them.
        // In case the configuration already contains such file, we should avoid adding it twice
        let gpxFiles = project.schemes.compactMap { scheme -> GroupFileElement? in
            guard case let .gpxFile(path) = scheme.runAction?.options.simulatedLocation else {
                return nil
            }

            return GroupFileElement(path: path, group: project.filesGroup)
        }

        fileElements.formUnion(gpxFiles)

        return fileElements
    }

    func targetFiles(target: Target) throws -> Set<GroupFileElement> {
        var files = Set<AbsolutePath>()
        files.formUnion(target.sources.map(\.path))
        files.formUnion(target.playgrounds)
        files.formUnion(target.coreDataModels.map(\.path))
        files.formUnion(target.coreDataModels.flatMap(\.versions))

        if let headers = target.headers {
            files.formUnion(headers.public)
            files.formUnion(headers.private)
            files.formUnion(headers.project)
        }

        // Support files
        if let infoPlist = target.infoPlist, let path = infoPlist.path {
            files.insert(path)
        }

        if let entitlements = target.entitlements {
            files.insert(entitlements)
        }

        // Config files
        target.settings?.configurations.xcconfigs().forEach { configFilePath in
            files.insert(configFilePath)
        }

        // Additional files
        files.formUnion(target.additionalFiles.map(\.path))

        // Elements
        var elements = Set<GroupFileElement>()
        elements.formUnion(files.map { GroupFileElement(path: $0, group: target.filesGroup) })
        elements.formUnion(target.resources.map {
            GroupFileElement(
                path: $0.path,
                group: target.filesGroup,
                isReference: $0.isReference
            )
        })

        target.copyFiles.forEach {
            elements.formUnion($0.files.map {
                GroupFileElement(
                    path: $0.path,
                    group: target.filesGroup,
                    isReference: $0.isReference
                )
            })
        }

        return elements
    }

    func generate(
        files: [GroupFileElement],
        groups: ProjectGroups,
        pbxproj: PBXProj,
        sourceRootPath: AbsolutePath
    ) throws {
        try files.forEach {
            try generate(fileElement: $0, groups: groups, pbxproj: pbxproj, sourceRootPath: sourceRootPath)
        }
    }

    func generate(
        dependencyReferences: Set<GraphDependencyReference>,
        groups: ProjectGroups,
        pbxproj: PBXProj,
        sourceRootPath: AbsolutePath,
        filesGroup: ProjectGroup
    ) throws {
        let sortedDependencies = dependencyReferences.sorted()

        func generatePrecompiled(_ path: AbsolutePath) throws {
            let fileElement = GroupFileElement(path: path, group: filesGroup)
            try generate(
                fileElement: fileElement,
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: sourceRootPath
            )
        }

        try sortedDependencies.forEach { dependency in
            switch dependency {
            case let .xcframework(path, _, _, _):
                try generatePrecompiled(path)
            case let .framework(path, _, _, _, _, _, _, _):
                try generatePrecompiled(path)
            case let .library(path, _, _, _):
                try generatePrecompiled(path)
            case let .bundle(path):
                try generatePrecompiled(path)
            case let .sdk(sdkNodePath, _, _):
                generateSDKFileElement(
                    sdkNodePath: sdkNodePath,
                    toGroup: groups.frameworks,
                    pbxproj: pbxproj
                )
            case let .product(target: target, productName: productName, _):
                generateProduct(
                    targetName: target,
                    productName: productName,
                    groups: groups,
                    pbxproj: pbxproj
                )
            }
        }
    }

    private func generateProduct(
        targetName: String,
        productName: String,
        groups: ProjectGroups,
        pbxproj: PBXProj
    ) {
        guard products[targetName] == nil else { return }
        let fileType = RelativePath(productName).extension.flatMap { Xcode.filetype(extension: $0) }
        let fileReference = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: fileType,
            path: productName,
            includeInIndex: false
        )

        pbxproj.add(object: fileReference)
        groups.products.children.append(fileReference)
        products[targetName] = fileReference
    }

    func generate(
        fileElement: GroupFileElement,
        groups: ProjectGroups,
        pbxproj: PBXProj,
        sourceRootPath: AbsolutePath
    ) throws {
        // The file already exists
        if elements[fileElement.path] != nil { return }

        let fileElementRelativeToSourceRoot = fileElement.path.relative(to: sourceRootPath)
        let closestRelativeRelativePath = closestRelativeElementPath(pathRelativeToSourceRoot: fileElementRelativeToSourceRoot)
        let closestRelativeAbsolutePath = sourceRootPath.appending(closestRelativeRelativePath)
        // Add the first relative element.
        let group: PBXGroup
        switch fileElement.group {
        case let .group(name: groupName):
            group = try groups.projectGroup(named: groupName)
        }
        guard let firstElement = addElement(
            relativePath: closestRelativeRelativePath,
            isLeaf: closestRelativeRelativePath == fileElementRelativeToSourceRoot,
            from: sourceRootPath,
            toGroup: group,
            pbxproj: pbxproj
        )
        else {
            return
        }

        // If it matches the file that we are adding or it's not a group we can exit.
        if (closestRelativeAbsolutePath == fileElement.path) || !(firstElement.element is PBXGroup) {
            return
        }

        var lastGroup: PBXGroup! = firstElement.element as? PBXGroup
        var lastPath: AbsolutePath = firstElement.path
        let components = fileElement.path.relative(to: lastPath).components
        for component in components.enumerated() {
            if lastGroup == nil { return }
            guard let element = addElement(
                relativePath: RelativePath(component.element),
                isLeaf: component.offset == components.count - 1,
                from: lastPath,
                toGroup: lastGroup!,
                pbxproj: pbxproj
            )
            else {
                return
            }
            lastGroup = element.element as? PBXGroup
            lastPath = element.path
        }
    }

    // MARK: - Internal

    @discardableResult func addElement(
        relativePath: RelativePath,
        isLeaf: Bool,
        from: AbsolutePath,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) -> (element: PBXFileElement, path: AbsolutePath)? {
        let absolutePath = from.appending(relativePath)
        if elements[absolutePath] != nil {
            return (element: elements[absolutePath]!, path: from.appending(relativePath))
        }

        // If the path is ../../xx we specify the name
        // to prevent Xcode from using that as a name.
        var name: String?
        let components = relativePath.components
        if components.count != 1 {
            name = components.last!
        }

        // Add the file element
        if isLocalized(path: absolutePath) {
            // Localized container (e.g. /path/to/en.lproj) we don't add it directly
            // an element will get added once the next path component is evaluated
            //
            // note: assumption here is a path to a nested resource is always provided
            return (element: toGroup, path: absolutePath)
        } else if isLocalized(path: from) {
            // Localized file (e.g. /path/to/en.lproj/foo.png)
            addLocalizedFile(
                localizedFile: absolutePath,
                toGroup: toGroup,
                pbxproj: pbxproj
            )
            return nil
        } else if isVersionGroup(path: absolutePath) {
            return addVersionGroupElement(
                from: from,
                folderAbsolutePath: absolutePath,
                folderRelativePath: relativePath,
                name: name,
                toGroup: toGroup,
                pbxproj: pbxproj
            )
        } else if !isLeaf {
            return addGroupElement(
                from: from,
                folderAbsolutePath: absolutePath,
                folderRelativePath: relativePath,
                name: name,
                toGroup: toGroup,
                pbxproj: pbxproj
            )
        } else {
            addFileElement(
                from: from,
                fileAbsolutePath: absolutePath,
                fileRelativePath: relativePath,
                name: name,
                toGroup: toGroup,
                pbxproj: pbxproj
            )
            return nil
        }
    }

    func addLocalizedFile(
        localizedFile: AbsolutePath,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) {
        // e.g.
        // from: resources/en.lproj/
        // localizedFile: resources/en.lproj/App.strings
        let fileName = localizedFile.basename // e.g. App.strings
        let localizedContainer = localizedFile.parentDirectory // e.g. resources/en.lproj
        let variantGroupPath = localizedContainer
            .parentDirectory
            .appending(component: fileName) // e.g. resources/App.strings

        let variantGroup: PBXVariantGroup
        if let existingVariantGroup = self.variantGroup(containing: localizedFile) {
            variantGroup = existingVariantGroup.group
            // For variant groups formed by Interface Builder files (.xib or .storyboard) and corresponding .strings
            // files, name and path of the group must have the extension of the Interface Builder file. Since the order
            // in which such groups are formed is not deterministic, we must change the name and path here as necessary.
            if ["xib", "storyboard"].contains(localizedFile.extension), !variantGroup.nameOrPath.hasSuffix(fileName) {
                variantGroup.name = fileName
                elements[existingVariantGroup.path] = nil
                elements[variantGroupPath] = variantGroup
            }
        } else {
            variantGroup = addVariantGroup(
                variantGroupPath: variantGroupPath,
                localizedName: fileName,
                toGroup: toGroup,
                pbxproj: pbxproj
            )
        }

        // Localized element
        addLocalizedFileElement(
            localizedFile: localizedFile,
            variantGroup: variantGroup,
            localizedContainer: localizedContainer,
            pbxproj: pbxproj
        )
    }

    private func addVariantGroup(
        variantGroupPath: AbsolutePath,
        localizedName: String,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) -> PBXVariantGroup {
        let variantGroup = PBXVariantGroup(children: [], sourceTree: .group, name: localizedName)
        pbxproj.add(object: variantGroup)
        toGroup.children.append(variantGroup)
        elements[variantGroupPath] = variantGroup
        return variantGroup
    }

    private func addLocalizedFileElement(
        localizedFile: AbsolutePath,
        variantGroup: PBXVariantGroup,
        localizedContainer: AbsolutePath,
        pbxproj: PBXProj
    ) {
        let localizedFilePath = localizedFile.relative(to: localizedContainer.parentDirectory)
        let lastKnownFileType = localizedFile.extension.flatMap { Xcode.filetype(extension: $0) }
        let language = localizedContainer.basenameWithoutExt
        let localizedFileReference = PBXFileReference(
            sourceTree: .group,
            name: language,
            lastKnownFileType: lastKnownFileType,
            path: localizedFilePath.pathString
        )
        pbxproj.add(object: localizedFileReference)
        variantGroup.children.append(localizedFileReference)
        knownRegions.insert(language)
    }

    func addVersionGroupElement(
        from: AbsolutePath,
        folderAbsolutePath: AbsolutePath,
        folderRelativePath: RelativePath,
        name: String?,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) -> (element: PBXFileElement, path: AbsolutePath) {
        let group = XCVersionGroup(
            currentVersion: nil,
            path: folderRelativePath.pathString,
            name: name,
            sourceTree: .group,
            versionGroupType: versionGroupType(for: folderRelativePath)
        )
        pbxproj.add(object: group)
        toGroup.children.append(group)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addGroupElement(
        from: AbsolutePath,
        folderAbsolutePath: AbsolutePath,
        folderRelativePath: RelativePath,
        name: String?,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) -> (element: PBXFileElement, path: AbsolutePath) {
        let group = PBXGroup(children: [], sourceTree: .group, name: name, path: folderRelativePath.pathString)
        pbxproj.add(object: group)
        toGroup.children.append(group)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addFileElement(
        from _: AbsolutePath,
        fileAbsolutePath: AbsolutePath,
        fileRelativePath: RelativePath,
        name: String?,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) {
        let lastKnownFileType = fileAbsolutePath.extension.flatMap { Xcode.filetype(extension: $0) }
        let xcLanguageSpecificationIdentifier = lastKnownFileType == "file.playground" ? "xcode.lang.swift" : nil
        let file = PBXFileReference(
            sourceTree: .group,
            name: name,
            lastKnownFileType: lastKnownFileType,
            path: fileRelativePath.pathString,
            xcLanguageSpecificationIdentifier: xcLanguageSpecificationIdentifier
        )
        pbxproj.add(object: file)
        toGroup.children.append(file)
        elements[fileAbsolutePath] = file
    }

    private func generateSDKFileElement(
        sdkNodePath: AbsolutePath,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) {
        guard sdks[sdkNodePath] == nil else {
            return
        }

        addSDKElement(sdkNodePath: sdkNodePath, toGroup: toGroup, pbxproj: pbxproj)
    }

    private func addSDKElement(
        sdkNodePath: AbsolutePath,
        toGroup: PBXGroup,
        pbxproj: PBXProj
    ) {
        // swiftlint:disable:next force_try
        let sdkPath = sdkNodePath.relative(to: try! AbsolutePath(validating: "/")) // SDK paths are relative

        let lastKnownFileType = sdkPath.extension.flatMap { Xcode.filetype(extension: $0) }
        let file = PBXFileReference(
            sourceTree: .developerDir,
            name: sdkPath.basename,
            lastKnownFileType: lastKnownFileType,
            path: sdkPath.pathString
        )
        pbxproj.add(object: file)
        toGroup.children.append(file)
        sdks[sdkNodePath] = file
    }

    func group(path: AbsolutePath) -> PBXGroup? {
        elements[path] as? PBXGroup
    }

    func product(target name: String) -> PBXFileReference? {
        products[name]
    }

    func sdk(path: AbsolutePath) -> PBXFileReference? {
        sdks[path]
    }

    func file(path: AbsolutePath) -> PBXFileReference? {
        elements[path] as? PBXFileReference
    }

    func isLocalized(path: AbsolutePath) -> Bool {
        path.extension == "lproj"
    }

    func isVersionGroup(path: AbsolutePath) -> Bool {
        path.extension == "xcdatamodeld"
    }

    /// Normalizes a path. Some paths have no direct representation in Xcode,
    /// like localizable files. This method normalizes those and returns a project
    /// representable path.
    ///
    /// - Example:
    ///   /test/es.lproj/Main.storyboard ~> /test/es.lproj
    func normalize(_ path: AbsolutePath) -> AbsolutePath {
        let pathString = path.pathString
        let range = NSRange(location: 0, length: pathString.count)
        if let localizedMatch = ProjectFileElements.localizedRegex.firstMatch(
            in: pathString,
            options: [],
            range: range
        ) {
            let lprojPath = (pathString as NSString).substring(with: localizedMatch.range(at: 1))
            return try! AbsolutePath(validating: lprojPath) // swiftlint:disable:this force_try
        } else {
            return path
        }
    }

    /// Returns the relative path of the closest relative element to the source root path.
    /// If source root path is /a/b/c/project/ and file path is /a/d/myfile.swift
    /// this method will return ../../../d/
    func closestRelativeElementPath(pathRelativeToSourceRoot: RelativePath) -> RelativePath {
        let relativePathComponents = pathRelativeToSourceRoot.components
        let firstElementComponents = relativePathComponents.reduce(into: [String]()) { components, component in
            let isLastRelative = components.last == ".." || components.last == "."
            if components.last != nil, !isLastRelative { return }
            components.append(component)
        }
        if firstElementComponents.isEmpty, !relativePathComponents.isEmpty {
            return RelativePath(relativePathComponents.first!)
        } else {
            return RelativePath(firstElementComponents.joined(separator: "/"))
        }
    }

    func variantGroup(containing localizedFile: AbsolutePath) -> (group: PBXVariantGroup, path: AbsolutePath)? {
        let variantGroupBasePath = localizedFile.parentDirectory.parentDirectory

        // Variant groups used to localize Interface Builder or Intent Definition files (.xib, .storyboard or .intentdefition)
        // can contain files of these, respectively, and corresponding .strings files. However, the groups' names must always
        // use the extension of the main file, i.e. either .xib or .storyboard. Since the order in which such
        // groups are formed is not deterministic, we must check for existing groups having the same name as the
        // localized file and any of these extensions.
        if let fileExtension = localizedFile.extension,
           Self.localizedGroupExtensions.contains(fileExtension)
        {
            for groupExtension in Self.localizedGroupExtensions {
                let variantGroupPath = variantGroupBasePath.appending(
                    component: "\(localizedFile.basenameWithoutExt).\(groupExtension)"
                )
                if let variantGroup = elements[variantGroupPath] as? PBXVariantGroup {
                    return (variantGroup, variantGroupPath)
                }
            }
        }

        let variantGroupPath = variantGroupBasePath.appending(component: localizedFile.basename)
        guard let variantGroup = elements[variantGroupPath] as? PBXVariantGroup else {
            return nil
        }

        return (variantGroup, variantGroupPath)
    }

    private func versionGroupType(for filePath: RelativePath) -> String? {
        switch filePath.extension {
        case "xcdatamodeld":
            return "wrapper.xcdatamodel"
        case let fileExtension?:
            return Xcode.filetype(extension: fileExtension)
        default:
            return nil
        }
    }
}
