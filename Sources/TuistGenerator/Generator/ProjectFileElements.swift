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
        var products = Set<String>()
        project.targets.forEach { target in
            files.formUnion(targetFiles(target: target))
            products.formUnion(targetProducts(target: target))
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

        /// Products
        generate(products: products.sorted(),
                 groups: groups,
                 pbxproj: pbxproj)

        /// Playgrounds
        generatePlaygrounds(path: project.path,
                            groups: groups,
                            pbxproj: pbxproj,
                            sourceRootPath: sourceRootPath)

        let dependencies = graph.findAll(path: project.path)

        /// Dependencies
        try generate(dependencies: dependencies,
                     path: project.path,
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

    func targetProducts(target: Target) -> Set<String> {
        var products: Set<String> = Set()
        products.insert(target.productNameWithExtension)
        return products
    }

    func targetFiles(target: Target) -> Set<GroupFileElement> {
        var files = Set<AbsolutePath>()
        files.formUnion(target.sources)
        files.formUnion(target.coreDataModels.map { $0.path })
        files.formUnion(target.coreDataModels.flatMap { $0.versions })

        if let headers = target.headers {
            files.formUnion(headers.public)
            files.formUnion(headers.private)
            files.formUnion(headers.project)
        }

        // Support files
        if let infoPlist = target.infoPlist {
            files.insert(infoPlist)
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

    func generate(products: [String],
                  groups: ProjectGroups,
                  pbxproj: PBXProj) {
        products.sorted().forEach { productName in
            if self.products[productName] != nil { return }
            let fileType = Xcode.filetype(extension: String(productName.split(separator: ".").last!))
            let fileReference = PBXFileReference(sourceTree: .buildProductsDir,
                                                 explicitFileType: fileType,
                                                 path: productName,
                                                 includeInIndex: false)
            pbxproj.add(object: fileReference)
            groups.products.children.append(fileReference)
            self.products[productName] = fileReference
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

    func generate(dependencies: Set<GraphNode>,
                  path: AbsolutePath,
                  groups: ProjectGroups,
                  pbxproj: PBXProj,
                  sourceRootPath: AbsolutePath,
                  filesGroup: ProjectGroup) throws {
        try dependencies.forEach { node in
            if let targetNode = node as? TargetNode {
                // Product name
                let productName = targetNode.target.productNameWithExtension
                if self.products[productName] != nil { return }

                /// The dependency belongs to the same project and its product
                /// has already been generated by generate(products:)
                if targetNode.path == path { return }

                // Add it
                let fileType = Xcode.filetype(extension: targetNode.target.product.xcodeValue.fileExtension!)
                let fileReference = PBXFileReference(sourceTree: .buildProductsDir,
                                                     explicitFileType: fileType,
                                                     path: productName,
                                                     includeInIndex: false)
                pbxproj.add(object: fileReference)
                groups.products.children.append(fileReference)
                self.products[productName] = fileReference

            } else if let precompiledNode = node as? PrecompiledNode {
                let fileElement = GroupFileElement(path: precompiledNode.path,
                                                   group: filesGroup)
                try generate(fileElement: fileElement,
                             groups: groups,
                             pbxproj: pbxproj,
                             sourceRootPath: sourceRootPath)
            }
        }
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
            addVariantGroup(from: from,
                            absolutePath: absolutePath,
                            relativePath: relativePath,
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

    func addVariantGroup(from: AbsolutePath,
                         absolutePath: AbsolutePath,
                         relativePath _: RelativePath,
                         toGroup: PBXGroup,
                         pbxproj: PBXProj) {
        // /path/to/*.lproj/*
        absolutePath.glob("*").sorted().forEach { localizedFile in
            let localizedName = localizedFile.components.last!

            // Variant group
            let variantGroupPath = absolutePath.parentDirectory.appending(component: localizedName)
            var variantGroup: PBXVariantGroup! = elements[variantGroupPath] as? PBXVariantGroup
            if variantGroup == nil {
                variantGroup = PBXVariantGroup(children: [], sourceTree: .group, name: localizedName)
                pbxproj.add(object: variantGroup)
                toGroup.children.append(variantGroup)
                elements[variantGroupPath] = variantGroup
            }

            // Localized element
            let localizedFilePath = "\(absolutePath.components.last!)/\(localizedName)" // e.g: en.lproj/Main.storyboard
            let lastKnownFileType = Xcode.filetype(extension: localizedName) // e.g. Main.storyboard
            let name = absolutePath.components.last!.split(separator: ".").first! // e.g. en
            let localizedFileReference = PBXFileReference(sourceTree: .group,
                                                          name: String(name),
                                                          lastKnownFileType: lastKnownFileType,
                                                          path: localizedFilePath)
            pbxproj.add(object: localizedFileReference)
            variantGroup.children.append(localizedFileReference)
        }
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

    func group(path: AbsolutePath) -> PBXGroup? {
        return elements[path] as? PBXGroup
    }

    func product(name: String) -> PBXFileReference? {
        return products[name]
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
