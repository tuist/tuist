import Basic
import Foundation
import TuistCore
import XcodeProj

// swiftlint:disable:next type_body_length
class ProjectFileElements {
    struct GroupFileElement: Hashable {
        var path: AbsolutePath
        var group: ProjectGroup
        var isReference: Bool

        init(path: AbsolutePath, group: ProjectGroup, isReference: Bool = false) {
            self.path = path
            self.group = group
            self.isReference = isReference
        }
    }

    // MARK: - Static

    // swiftlint:disable:next force_try
    static let localizedRegex = try! NSRegularExpression(pattern: "(.+\\.lproj)/.+",
                                                         options: [])
    // swiftlint:disable:next force_try
    static let assetRegex = try! NSRegularExpression(pattern: ".+/.+\\.xcassets/.+",
                                                     options: [])

    // MARK: - Attributes

    var elements: [AbsolutePath: PBXFileElement] = [:]
    var products: [String: PBXFileReference] = [:]
    var sdks: [AbsolutePath: PBXFileReference] = [:]
    let playgrounds: Playgrounding
    let filesSortener: ProjectFilesSortening

    // MARK: - Init

    init(_ elements: [AbsolutePath: PBXFileElement] = [:],
         playgrounds: Playgrounding = Playgrounds(),
         filesSortener: ProjectFilesSortening = ProjectFilesSortener()) {
        self.elements = elements
        self.playgrounds = playgrounds
        self.filesSortener = filesSortener
    }

    func generateProjectFiles(project: Project,
                              graph: Graphing,
                              groups: ProjectGroups,
                              pbxproj: PBXProj,
                              sourceRootPath: AbsolutePath) throws {
        var files = Set<GroupFileElement>()

        try project.targets.forEach { target in
            try files.formUnion(targetFiles(target: target, projectPath: project.path, graph: graph))
        }
        let projectFileElements = projectFiles(project: project)
        files.formUnion(projectFileElements)

        let pathsSort = filesSortener.sort
        let filesSort: (GroupFileElement, GroupFileElement) -> Bool = {
            pathsSort($0.path, $1.path)
        }

        /// Files
        try generate(files: files.sorted(by: filesSort),
                     groups: groups,
                     pbxproj: pbxproj,
                     sourceRootPath: sourceRootPath)

        /// Playgrounds
        generatePlaygrounds(path: project.path,
                            groups: groups,
                            pbxproj: pbxproj,
                            sourceRootPath: sourceRootPath)

        // Products
        let directProducts = project.targets.map {
            DependencyReference.product(target: $0.name, productName: $0.productNameWithExtension)
        }

        // Dependencies
        let dependencies = try graph.allDependencyReferences(for: project)

        try generate(dependencyReferences: Set(directProducts + dependencies),
                     groups: groups,
                     pbxproj: pbxproj,
                     sourceRootPath: sourceRootPath,
                     filesGroup: project.filesGroup)
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
            GroupFileElement(path: $0.path,
                             group: project.filesGroup,
                             isReference: $0.isReference)
        })

        return fileElements
    }

    func targetFiles(target: Target, projectPath: AbsolutePath, graph: Graphing) throws -> Set<GroupFileElement> {
        var files = Set<AbsolutePath>()
        files.formUnion(target.sources.map { $0.path })
        files.formUnion(target.coreDataModels.map { $0.path })
        files.formUnion(target.coreDataModels.flatMap { $0.versions })

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

        // Elements
        var elements = Set<GroupFileElement>()
        elements.formUnion(files.map { GroupFileElement(path: $0, group: target.filesGroup) })
        elements.formUnion(target.resources.map {
            GroupFileElement(path: $0.path,
                             group: target.filesGroup,
                             isReference: $0.isReference)
        })

        // Local Packages
        elements.formUnion(
            try graph.packages(path: projectPath, name: target.name).compactMap { node -> GroupFileElement? in
                switch node.packageType {
                case let .local(path: packagePath, productName: _):
                    return GroupFileElement(path: projectPath.appending(packagePath),
                                            group: target.filesGroup,
                                            isReference: true)
                default:
                    return nil
                }
            }
        )

        return elements
    }

    func generate(files: [GroupFileElement],
                  groups: ProjectGroups,
                  pbxproj: PBXProj,
                  sourceRootPath: AbsolutePath) throws {
        try files.forEach {
            try generate(fileElement: $0, groups: groups, pbxproj: pbxproj, sourceRootPath: sourceRootPath)
        }
    }

    func generatePlaygrounds(path: AbsolutePath,
                             groups: ProjectGroups,
                             pbxproj: PBXProj,
                             sourceRootPath _: AbsolutePath) {
        let paths = playgrounds.paths(path: path)
        if paths.isEmpty { return }

        let group = groups.playgrounds
        paths.forEach { playgroundPath in
            let name = playgroundPath.components.last!
            let reference = PBXFileReference(sourceTree: .group,
                                             lastKnownFileType: "file.playground",
                                             path: name,
                                             xcLanguageSpecificationIdentifier: "xcode.lang.swift")
            pbxproj.add(object: reference)
            group!.children.append(reference)
        }
    }

    func generate(dependencyReferences: Set<DependencyReference>,
                  groups: ProjectGroups,
                  pbxproj: PBXProj,
                  sourceRootPath: AbsolutePath,
                  filesGroup: ProjectGroup) throws {
        let sortedDependencies = dependencyReferences.sorted()
        try sortedDependencies.forEach { dependency in
            switch dependency {
            case let .absolute(dependencyPath):
                let fileElement = GroupFileElement(path: dependencyPath,
                                                   group: filesGroup)
                try generate(fileElement: fileElement,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: sourceRootPath)
            case let .sdk(sdkNodePath, _):
                generateSDKFileElement(sdkNodePath: sdkNodePath,
                                       toGroup: groups.frameworks,
                                       pbxproj: pbxproj)
            case let .product(target: target, productName: productName):
                generateProduct(targetName: target,
                                productName: productName,
                                groups: groups,
                                pbxproj: pbxproj)
            }
        }
    }

    private func generateProduct(targetName: String,
                                 productName: String,
                                 groups: ProjectGroups,
                                 pbxproj: PBXProj) {
        guard products[targetName] == nil else { return }
        let fileType = RelativePath(productName).extension.flatMap { Xcode.filetype(extension: $0) }
        let fileReference = PBXFileReference(sourceTree: .buildProductsDir,
                                             explicitFileType: fileType,
                                             path: productName,
                                             includeInIndex: false)

        pbxproj.add(object: fileReference)
        groups.products.children.append(fileReference)
        products[targetName] = fileReference
    }

    func generate(fileElement: GroupFileElement,
                  groups: ProjectGroups,
                  pbxproj: PBXProj,
                  sourceRootPath: AbsolutePath) throws {
        // The file already exists
        if elements[fileElement.path] != nil { return }

        let closestRelativeRelativePath = closestRelativeElementPath(path: fileElement.path,
                                                                     sourceRootPath: sourceRootPath)
        let closestRelativeAbsolutePath = sourceRootPath.appending(closestRelativeRelativePath)
        let fileElementRelativeToSourceRoot = fileElement.path.relative(to: sourceRootPath)
        // Add the first relative element.
        let group: PBXGroup
        switch fileElement.group {
        case let .group(name: groupName):
            group = try groups.projectGroup(named: groupName)
        }
        guard let firstElement = addElement(relativePath: closestRelativeRelativePath,
                                            isLeaf: closestRelativeRelativePath == fileElementRelativeToSourceRoot,
                                            from: sourceRootPath,
                                            toGroup: group,
                                            pbxproj: pbxproj) else {
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
            guard let element = addElement(relativePath: RelativePath(component.element),
                                           isLeaf: component.offset == components.count - 1,
                                           from: lastPath,
                                           toGroup: lastGroup!,
                                           pbxproj: pbxproj) else {
                return
            }
            lastGroup = element.element as? PBXGroup
            lastPath = element.path
        }
    }

    // MARK: - Internal

    @discardableResult func addElement(relativePath: RelativePath,
                                       isLeaf: Bool,
                                       from: AbsolutePath,
                                       toGroup: PBXGroup,
                                       pbxproj: PBXProj) -> (element: PBXFileElement, path: AbsolutePath)? {
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
            addLocalizedFile(localizedFile: absolutePath,
                             toGroup: toGroup,
                             pbxproj: pbxproj)
            return nil
        } else if isVersionGroup(path: absolutePath) {
            return addVersionGroupElement(from: from,
                                          folderAbsolutePath: absolutePath,
                                          folderRelativePath: relativePath,
                                          name: name,
                                          toGroup: toGroup,
                                          pbxproj: pbxproj)
        } else if !(isXcassets(path: absolutePath) || isLeaf) {
            return addGroupElement(from: from,
                                   folderAbsolutePath: absolutePath,
                                   folderRelativePath: relativePath,
                                   name: name,
                                   toGroup: toGroup,
                                   pbxproj: pbxproj)
        } else {
            addFileElement(from: from,
                           fileAbsolutePath: absolutePath,
                           fileRelativePath: relativePath,
                           name: name,
                           toGroup: toGroup,
                           pbxproj: pbxproj)
            return nil
        }
    }

    func addLocalizedFile(localizedFile: AbsolutePath,
                          toGroup: PBXGroup,
                          pbxproj: PBXProj) {
        // e.g.
        // from: resources/en.lproj/
        // localizedFile: resources/en.lproj/App.strings

        // Variant Group
        let localizedName = localizedFile.basename // e.g. App.strings
        let localizedContainer = localizedFile.parentDirectory // e.g. resources/en.lproj
        let variantGroupPath = localizedContainer
            .parentDirectory
            .appending(component: localizedName) // e.g. resources/App.strings

        let variantGroup = addVariantGroup(variantGroupPath: variantGroupPath,
                                           localizedName: localizedName,
                                           toGroup: toGroup,
                                           pbxproj: pbxproj)

        // Localized element
        addLocalizedFileElement(localizedFile: localizedFile,
                                variantGroup: variantGroup,
                                localizedContainer: localizedContainer,
                                pbxproj: pbxproj)
    }

    private func addVariantGroup(variantGroupPath: AbsolutePath,
                                 localizedName: String,
                                 toGroup: PBXGroup,
                                 pbxproj: PBXProj) -> PBXVariantGroup {
        if let variantGroup = elements[variantGroupPath] as? PBXVariantGroup {
            return variantGroup
        }

        let variantGroup = PBXVariantGroup(children: [], sourceTree: .group, name: localizedName)
        pbxproj.add(object: variantGroup)
        toGroup.children.append(variantGroup)
        elements[variantGroupPath] = variantGroup
        return variantGroup
    }

    private func addLocalizedFileElement(localizedFile: AbsolutePath,
                                         variantGroup: PBXVariantGroup,
                                         localizedContainer: AbsolutePath,
                                         pbxproj: PBXProj) {
        let localizedFilePath = localizedFile.relative(to: localizedContainer.parentDirectory)
        let lastKnownFileType = localizedFile.extension.flatMap { Xcode.filetype(extension: $0) }
        let name = localizedContainer.basename.split(separator: ".").first
        let localizedFileReference = PBXFileReference(sourceTree: .group,
                                                      name: name.map { String($0) },
                                                      lastKnownFileType: lastKnownFileType,
                                                      path: localizedFilePath.pathString)
        pbxproj.add(object: localizedFileReference)
        variantGroup.children.append(localizedFileReference)
    }

    func addVersionGroupElement(from: AbsolutePath,
                                folderAbsolutePath: AbsolutePath,
                                folderRelativePath: RelativePath,
                                name: String?,
                                toGroup: PBXGroup,
                                pbxproj: PBXProj) -> (element: PBXFileElement, path: AbsolutePath) {
        let versionGroupType = Xcode.filetype(extension: folderRelativePath.extension!)
        let group = XCVersionGroup(currentVersion: nil,
                                   path: folderRelativePath.pathString,
                                   name: name,
                                   sourceTree: .group,
                                   versionGroupType: versionGroupType)
        pbxproj.add(object: group)
        toGroup.children.append(group)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addGroupElement(from: AbsolutePath,
                         folderAbsolutePath: AbsolutePath,
                         folderRelativePath: RelativePath,
                         name: String?,
                         toGroup: PBXGroup,
                         pbxproj: PBXProj) -> (element: PBXFileElement, path: AbsolutePath) {
        let group = PBXGroup(children: [], sourceTree: .group, name: name, path: folderRelativePath.pathString)
        pbxproj.add(object: group)
        toGroup.children.append(group)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addFileElement(from _: AbsolutePath,
                        fileAbsolutePath: AbsolutePath,
                        fileRelativePath: RelativePath,
                        name: String?,
                        toGroup: PBXGroup,
                        pbxproj: PBXProj) {
        let lastKnownFileType = fileAbsolutePath.extension.flatMap { Xcode.filetype(extension: $0) }
        let file = PBXFileReference(sourceTree: .group, name: name, lastKnownFileType: lastKnownFileType, path: fileRelativePath.pathString)
        pbxproj.add(object: file)
        toGroup.children.append(file)
        elements[fileAbsolutePath] = file
    }

    private func generateSDKFileElement(sdkNodePath: AbsolutePath,
                                        toGroup: PBXGroup,
                                        pbxproj: PBXProj) {
        guard sdks[sdkNodePath] == nil else {
            return
        }

        addSDKElement(sdkNodePath: sdkNodePath, toGroup: toGroup, pbxproj: pbxproj)
    }

    private func addSDKElement(sdkNodePath: AbsolutePath,
                               toGroup: PBXGroup,
                               pbxproj: PBXProj) {
        let sdkPath = sdkNodePath.relative(to: AbsolutePath("/")) // SDK paths are relative

        let lastKnownFileType = sdkPath.extension.flatMap { Xcode.filetype(extension: $0) }
        let file = PBXFileReference(sourceTree: .developerDir,
                                    name: sdkPath.basename,
                                    lastKnownFileType: lastKnownFileType,
                                    path: sdkPath.pathString)
        pbxproj.add(object: file)
        toGroup.children.append(file)
        sdks[sdkNodePath] = file
    }

    func group(path: AbsolutePath) -> PBXGroup? {
        return elements[path] as? PBXGroup
    }

    func product(target name: String) -> PBXFileReference? {
        return products[name]
    }

    func sdk(path: AbsolutePath) -> PBXFileReference? {
        return sdks[path]
    }

    func file(path: AbsolutePath) -> PBXFileReference? {
        return elements[path] as? PBXFileReference
    }

    func isLocalized(path: AbsolutePath) -> Bool {
        return path.extension == "lproj"
    }

    func isVersionGroup(path: AbsolutePath) -> Bool {
        return path.extension == "xcdatamodeld"
    }

    func isXcassets(path: AbsolutePath) -> Bool {
        return path.extension == "xcassets"
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
        if let localizedMatch = ProjectFileElements.localizedRegex.firstMatch(in: pathString,
                                                                              options: [],
                                                                              range: range) {
            let lprojPath = (pathString as NSString).substring(with: localizedMatch.range(at: 1))
            return AbsolutePath(lprojPath)
        } else {
            return path
        }
    }

    /// Returns the relative path of the closest relative element to the source root path.
    /// If source root path is /a/b/c/project/ and file path is /a/d/myfile.swift
    /// this method will return ../../../d/
    func closestRelativeElementPath(path: AbsolutePath, sourceRootPath: AbsolutePath) -> RelativePath {
        let relativePathComponents = path.relative(to: sourceRootPath).components
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
}
