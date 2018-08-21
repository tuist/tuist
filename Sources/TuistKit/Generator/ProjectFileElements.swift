import Basic
import Foundation
import xcodeproj

class ProjectFileElements {

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

    // MARK: - Init

    init(_ elements: [AbsolutePath: PBXFileElement] = [:]) {
        self.elements = elements
    }

    func generateProjectFiles(project: Project,
                              graph: Graphing,
                              groups: ProjectGroups,
                              objects: PBXObjects,
                              sourceRootPath: AbsolutePath) {
        var files = Set<AbsolutePath>()
        var products = Set<String>()
        project.targets.forEach { target in
            files.formUnion(targetFiles(target: target))
            products.formUnion(targetProducts(target: target))
        }
        files.formUnion(projectFiles(project: project))

        /// Files
        generate(files: files.sorted(),
                 groups: groups,
                 objects: objects,
                 sourceRootPath: sourceRootPath)

        /// Products
        generate(products: products.sorted(),
                 groups: groups,
                 objects: objects)

        /// Playgrounds
        generatePlaygrounds(path: project.path,
                            groups: groups,
                            objects: objects,
                            sourceRootPath: sourceRootPath)

        /// Dependencies
        generate(dependencies: graph.dependencies(path: project.path),
                 path: project.path,
                 groups: groups,
                 objects: objects,
                 sourceRootPath: sourceRootPath)
    }

    func projectFiles(project: Project) -> Set<AbsolutePath> {
        var files = Set<AbsolutePath>()

        /// Config files
        if let debugConfigFile = project.settings?.debug?.xcconfig {
            files.insert(debugConfigFile)
        }
        if let releaseConfigFile = project.settings?.release?.xcconfig {
            files.insert(releaseConfigFile)
        }
        return files
    }

    func targetProducts(target: Target) -> Set<String> {
        var products: Set<String> = Set()
        products.insert(target.productName)
        return products
    }

    func targetFiles(target: Target) -> Set<AbsolutePath> {
        var files = Set<AbsolutePath>()
        files.formUnion(target.sources)
        files.formUnion(target.resources)
        files.formUnion(target.coreDataModels.map({ $0.path }))
        files.formUnion(target.coreDataModels.flatMap({ $0.versions }))

        if let headers = target.headers {
            files.formUnion(headers.public)
            files.formUnion(headers.private)
            files.formUnion(headers.project)
        }

        // Support files
        files.insert(target.infoPlist)
        if let entitlements = target.entitlements {
            files.insert(entitlements)
        }

        // Config files
        if let debugConfigFile = target.settings?.debug?.xcconfig {
            files.insert(debugConfigFile)
        }
        if let releaseConfigFile = target.settings?.release?.xcconfig {
            files.insert(releaseConfigFile)
        }
        return files
    }

    func generate(files: [AbsolutePath],
                  groups: ProjectGroups,
                  objects: PBXObjects,
                  sourceRootPath: AbsolutePath) {
        files.forEach({ generate(path: $0, groups: groups, objects: objects, sourceRootPath: sourceRootPath) })
    }

    func generate(products: [String],
                  groups: ProjectGroups,
                  objects: PBXObjects) {
        products.forEach { productName in
            if self.products[productName] != nil { return }
            let fileType = Xcode.filetype(extension: String(productName.split(separator: ".").last!))
            let fileReference = PBXFileReference(sourceTree: .buildProductsDir,
                                                 explicitFileType: fileType,
                                                 path: productName,
                                                 includeInIndex: false)
            let objectFileReference = objects.addObject(fileReference)
            groups.products.childrenReferences.append(objectFileReference)
            self.products[productName] = fileReference
        }
    }

    func generatePlaygrounds(path: AbsolutePath,
                             groups: ProjectGroups,
                             objects: PBXObjects,
                             sourceRootPath _: AbsolutePath) {
        let paths = path.glob("Playgrounds/*.playground").sorted()
        let group = groups.playgrounds
        paths.forEach { playgroundPath in
            let name = playgroundPath.components.last!
            let reference = PBXFileReference(sourceTree: .group,
                                             lastKnownFileType: "file.playground",
                                             path: name,
                                             xcLanguageSpecificationIdentifier: "xcode.lang.swift")
            let fileReferenceReference = objects.addObject(reference)
            group.childrenReferences.append(fileReferenceReference)
        }
    }

    func generate(dependencies: Set<GraphNode>,
                  path: AbsolutePath,
                  groups: ProjectGroups,
                  objects: PBXObjects,
                  sourceRootPath: AbsolutePath) {
        dependencies.forEach { node in
            if let targetNode = node as? TargetNode {
                // Product name
                let productName = targetNode.target.productName
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
                let objectFileReference = objects.addObject(fileReference)
                groups.products.childrenReferences.append(objectFileReference)
                self.products[productName] = fileReference

            } else if let precompiledNode = node as? PrecompiledNode {
                generate(path: precompiledNode.path,
                         groups: groups,
                         objects: objects,
                         sourceRootPath: sourceRootPath)
            }
        }
    }

    func generate(path: AbsolutePath,
                  groups: ProjectGroups,
                  objects: PBXObjects,
                  sourceRootPath: AbsolutePath) {
        // The file already exists
        if elements[path] != nil { return }

        let closestRelativeRelativePath = closestRelativeElementPath(path: path, sourceRootPath: sourceRootPath)
        let closestRelativeAbsolutePath = sourceRootPath.appending(closestRelativeRelativePath)

        // Add the first relative element.
        guard let firstElement = addElement(relativePath: closestRelativeRelativePath, from: sourceRootPath, toGroup: groups.project, objects: objects) else {
            return
        }

        // If it matches the file that we are adding or it's not a group we can exit.
        if (closestRelativeAbsolutePath == path) || !(firstElement.element is PBXGroup) {
            return
        }

        // swiftlint:disable:next force_cast
        var lastGroup: PBXGroup! = firstElement.element as! PBXGroup
        var lastPath: AbsolutePath = firstElement.path

        for component in path.relative(to: lastPath).components {
            if lastGroup == nil { return }
            guard let element = addElement(relativePath: RelativePath(component),
                                           from: lastPath,
                                           toGroup: lastGroup!,
                                           objects: objects) else {
                return
            }
            lastGroup = element.element as? PBXGroup
            lastPath = element.path
        }
    }

    // MARK: - Internal

    @discardableResult func addElement(relativePath: RelativePath,
                                       from: AbsolutePath,
                                       toGroup: PBXGroup,
                                       objects: PBXObjects) -> (element: PBXFileElement, path: AbsolutePath)? {
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
                            objects: objects)
            return nil
        } else if isVersionGroup(path: absolutePath) {
            return addVersionGroupElement(from: from,
                                          folderAbsolutePath: absolutePath,
                                          folderRelativePath: relativePath,
                                          name: name,
                                          toGroup: toGroup,
                                          objects: objects)
        } else if isGroup(path: absolutePath) {
            return addGroupElement(from: from,
                                   folderAbsolutePath: absolutePath,
                                   folderRelativePath: relativePath,
                                   name: name,
                                   toGroup: toGroup,
                                   objects: objects)
        } else {
            addFileElement(from: from,
                           fileAbsolutePath: absolutePath,
                           fileRelativePath: relativePath,
                           name: name,
                           toGroup: toGroup,
                           objects: objects)
            return nil
        }
    }

    func addVariantGroup(from: AbsolutePath,
                         absolutePath: AbsolutePath,
                         relativePath _: RelativePath,
                         toGroup: PBXGroup,
                         objects: PBXObjects) {
        // /path/to/*.lproj/*
        absolutePath.glob("*").forEach { localizedFile in
            let localizedName = localizedFile.components.last!

            // Variant group
            let variantGroupPath = absolutePath.parentDirectory.appending(component: localizedName)
            var variantGroup: PBXVariantGroup! = elements[variantGroupPath] as? PBXVariantGroup
            if variantGroup == nil {
                variantGroup = PBXVariantGroup(sourceTree: .group, name: localizedName)
                let variantGroupReference = objects.addObject(variantGroup)
                toGroup.childrenReferences.append(variantGroupReference)
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
            let localizedFileReferenceReference = objects.addObject(localizedFileReference)
            variantGroup.childrenReferences.append(localizedFileReferenceReference)
        }
    }

    func addVersionGroupElement(from: AbsolutePath,
                                folderAbsolutePath: AbsolutePath,
                                folderRelativePath: RelativePath,
                                name: String?,
                                toGroup: PBXGroup,
                                objects: PBXObjects) -> (element: PBXFileElement, path: AbsolutePath) {
        let versionGroupType = Xcode.filetype(extension: folderRelativePath.extension!)
        let group = XCVersionGroup(currentVersion: nil,
                                   path: folderRelativePath.asString,
                                   name: name,
                                   sourceTree: .group,
                                   versionGroupType: versionGroupType)
        let reference = objects.addObject(group)
        toGroup.childrenReferences.append(reference)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addGroupElement(from: AbsolutePath,
                         folderAbsolutePath: AbsolutePath,
                         folderRelativePath: RelativePath,
                         name: String?,
                         toGroup: PBXGroup,
                         objects: PBXObjects) -> (element: PBXFileElement, path: AbsolutePath) {
        let group = PBXGroup(childrenReferences: [], sourceTree: .group, name: name, path: folderRelativePath.asString)
        let reference = objects.addObject(group)
        toGroup.childrenReferences.append(reference)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    func addFileElement(from _: AbsolutePath,
                        fileAbsolutePath: AbsolutePath,
                        fileRelativePath: RelativePath,
                        name: String?,
                        toGroup: PBXGroup,
                        objects: PBXObjects) {
        let lastKnownFileType = Xcode.filetype(extension: fileAbsolutePath.extension!)
        let file = PBXFileReference(sourceTree: .group, name: name, lastKnownFileType: lastKnownFileType, path: fileRelativePath.asString)
        let reference = objects.addObject(file)
        toGroup.childrenReferences.append(reference)
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

    func isGroup(path: AbsolutePath) -> Bool {
        return !isVersionGroup(path: path) && path.extension == nil
    }

    /// Normalizes a path. Some paths have no direct representation in Xcode,
    /// like localizable files. This method normalizes those and returns a project
    /// representable path.
    ///
    /// - Example:
    ///   /test/es.lproj/Main.storyboard ~> /test/es.lproj
    func normalize(_ path: AbsolutePath) -> AbsolutePath {
        let pathString = path.asString
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
            if components.last != nil && !isLastRelative { return }
            components.append(component)
        }
        if firstElementComponents.count == 0 && relativePathComponents.count != 0 {
            return RelativePath(relativePathComponents.first!)
        } else {
            return RelativePath(firstElementComponents.joined(separator: "/"))
        }
    }
}
