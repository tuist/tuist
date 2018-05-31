import Basic
import Foundation
import xcodeproj

class ProjectFileElements {
    /// Regex used to match localized files (inside .lproj folders)
    // swiftlint:disable:next force_try
    static let localizedRegex = try! NSRegularExpression(pattern: "(.+\\.lproj)/.+",
                                                         options: [])

    /// Elements.
    var elements: [AbsolutePath: PBXFileElement] = [:]

    /// Products.
    var products: [String: PBXFileReference] = [:]

    /// Default constructor.
    init(_ elements: [AbsolutePath: PBXFileElement] = [:]) {
        self.elements = elements
    }

    /// Generates all the project files.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - graph: dependencies graph.
    ///   - groups: project groups.
    ///   - objects: project objects.
    ///   - sourceRootPath: source root path.
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
        
        /// Dependencies
        generate(dependencies: graph.dependencies(path: project.path),
                 path: project.path,
                 groups: groups,
                 objects: objects,
                 sourceRootPath: sourceRootPath)
    }

    /// Returns the project file.
    ///
    /// - Parameters:
    ///   - project: project specification.
    ///   - graph: dependencies graph.
    /// - Returns: project files that should be generated.
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

    /// Returns the list of the target associated product, including the target product
    /// and any product that should be copied from a build phase.
    ///
    /// - Parameter target: target specification.
    /// - Returns: product names.
    func targetProducts(target: Target) -> Set<String> {
        var products: Set<String> = Set()
        products.insert(target.productName)
        target.buildPhases
            .compactMap({ $0 as? CopyBuildPhase })
            .flatMap({ $0.files })
            .forEach { buildFile in
                if case let CopyBuildFile.product(product) = buildFile {
                    products.insert(product)
                }
            }
        return products
    }

    /// Generates the target files.
    ///
    /// - Parameters:
    ///   - target: target whose files will be generated.
    ///   - groups: project groups.
    ///   - objects: project objects.
    ///   - sourceRootPath: project source root path.
    func targetFiles(target: Target) -> Set<AbsolutePath> {
        var files = Set<AbsolutePath>()
        target.buildPhases.forEach { buildPhase in
            // Sources
            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
                files.formUnion(sourcesBuildPhase.buildFiles.flatMap({ $0.paths }))

                // Resources
            } else if let resourcesBuildPhase = buildPhase as? ResourcesBuildPhase {
                resourcesBuildPhase.buildFiles.forEach { buildFile in

                    // Normal resources
                    if let resourceBuildFile = buildFile as? ResourcesBuildFile {
                        files.formUnion(resourceBuildFile.paths.map(normalize))

                        // Core Data model resoureces
                    } else if let coreDataModelBuildFile = buildFile as? CoreDataModelBuildFile {
                        files.insert(coreDataModelBuildFile.path)
                        files.formUnion(coreDataModelBuildFile.versions)
                    }
                }

                // Headers
            } else if let headersBuildPhase = buildPhase as? HeadersBuildPhase {
                files.formUnion(headersBuildPhase.buildFiles.flatMap({ $0.paths }))
                // Copy
            } else if let copyFilesBuildPhase = buildPhase as? CopyBuildPhase {
                copyFilesBuildPhase.files.forEach { buildFile in
                    if case let CopyBuildFile.path(path) = buildFile {
                        files.insert(path)
                    }
                }
            }
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

    /// Generates files in the project.
    ///
    /// - Parameters:
    ///   - files: files absolute paths.
    ///   - groups: project groups.
    ///   - objects: project objects.
    ///   - sourceRootPath: project source root path.
    func generate(files: [AbsolutePath],
                  groups: ProjectGroups,
                  objects: PBXObjects,
                  sourceRootPath: AbsolutePath) {
        files.forEach({ generate(path: $0, groups: groups, objects: objects, sourceRootPath: sourceRootPath) })
    }

    /// Generates file references for products.
    ///
    /// - Parameters:
    ///   - products: products whose references will be generated.
    ///   - groups: Xcode project groups.
    ///   - objects: Xcode project objects.
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
            groups.products.children.append(objectFileReference)
            self.products[productName] = fileReference
        }
    }
    
    /// Generates the references for the dependencies products. Those dependencies can be
    /// targets in the same project, in other projects or precompiled. If dependencies are
    /// other targets, the file references are generated in the products group, otherwise
    /// they are generated matching their relative path to the project.
    ///
    /// - Parameters:
    ///   - dependencies: dependencies whose products will be generated.
    ///   - path: path to the folder that contains the project definition.
    ///   - groups: project groups.
    ///   - objects: Xcode project objects.
    ///   - sourceRootPath: path to the folder that contains the Xcode project that is being generated.
    func generate(dependencies: Set<GraphNode>,
                  path: AbsolutePath,
                  groups: ProjectGroups,
                  objects: PBXObjects,
                  sourceRootPath: AbsolutePath) {
        dependencies.forEach { node in
            if let targetNode = node as? TargetNode {
                // Product name
                let name = targetNode.target.name
                let `extension` = targetNode.target.product.xcodeValue.fileExtension!
                let productName = "\(name).\(`extension`)"
                if self.products[productName] != nil { return }
                
                /// The dependency belongs to the same project and its product
                /// has already been generated by generate(products:)
                if targetNode.path == path { return }
                
                // Add it
                let fileType = Xcode.filetype(extension: `extension`)
                let fileReference = PBXFileReference(sourceTree: .buildProductsDir,
                                                     explicitFileType: fileType,
                                                     path: productName,
                                                     includeInIndex: false)
                let objectFileReference = objects.addObject(fileReference)
                groups.products.children.append(objectFileReference)
                self.products[productName] = fileReference

            } else if let precompiledNode = node as? PrecompiledNode {
                generate(path: precompiledNode.path,
                         groups: groups,
                         objects: objects,
                         sourceRootPath: sourceRootPath)
            }
        }
    }

    /// Generates a folder or file in the project. The folder or file gets added to the Files root group.
    ///
    /// - Parameters:
    ///   - path: file or folder absolute path.
    ///   - groups: project groups.
    ///   - objects: project objects.
    ///   - sourceRootPath: project source root path.
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

    // MARK: - Fileprivate

    /// Adds a new file or group to an existing group.
    ///
    /// - Parameters:
    ///   - relative: relative path from the group that is passed.
    ///   - from: absolute path of the group that is passed.
    ///   - toGroup: group where the file/group should be added.
    ///   - objects: project objects.
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

    /// Adds a localized element/s
    ///
    /// - Parameters:
    ///   - from: absolute path of the group the group is being added to.
    ///   - absolutePath: localized file absolute path.
    ///   - relativePath: localized path relative to the group absolute path.
    ///   - toGroup: group where the new group will be added.
    ///   - objects: Xcode project objects.
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
                toGroup.children.append(variantGroupReference)
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
            variantGroup.children.append(localizedFileReferenceReference)
        }
    }

    /// Adds a version group element.
    ///
    /// - Parameters:
    ///   - from: absolute path of the group the group is being added to.
    ///   - folderAbsolutePath: folder absolute path.
    ///   - folderRelativePath: folder path relative to the group absolute path.
    ///   - name: element name.
    ///   - toGroup: group where the new group will be added.
    ///   - objects: Xcode project objects.
    /// - Returns: added group.
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
        toGroup.children.append(reference)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    /// Adds a normal group element.
    ///
    /// - Parameters:
    ///   - from: absolute path of the group the group is being added to.
    ///   - folderAbsolutePath: folder absolute path.
    ///   - folderRelativePath: folder path relative to the group absolute path.
    ///   - name: element name.
    ///   - toGroup: group where the new group will be added.
    ///   - objects: Xcode project objects.
    /// - Returns: added group.
    func addGroupElement(from: AbsolutePath,
                         folderAbsolutePath: AbsolutePath,
                         folderRelativePath: RelativePath,
                         name: String?,
                         toGroup: PBXGroup,
                         objects: PBXObjects) -> (element: PBXFileElement, path: AbsolutePath) {
        let group = PBXGroup(children: [], sourceTree: .group, name: name, path: folderRelativePath.asString)
        let reference = objects.addObject(group)
        toGroup.children.append(reference)
        elements[folderAbsolutePath] = group
        return (element: group, path: from.appending(folderRelativePath))
    }

    /// Adds a file element.
    ///
    /// - Parameters:
    ///   - from: absolute path of the group the file is being added to.
    ///   - fileAbsolutePath: file absolute path.
    ///   - fileRelativePath: file path relative to the group absolute path.
    ///   - name: element name.
    ///   - toGroup: group where the file will be added.
    ///   - objects: Xcode project objects.
    func addFileElement(from _: AbsolutePath,
                        fileAbsolutePath: AbsolutePath,
                        fileRelativePath: RelativePath,
                        name: String?,
                        toGroup: PBXGroup,
                        objects: PBXObjects) {
        let lastKnownFileType = Xcode.filetype(extension: fileAbsolutePath.extension!)
        let file = PBXFileReference(sourceTree: .group, name: name, lastKnownFileType: lastKnownFileType, path: fileRelativePath.asString)
        let reference = objects.addObject(file)
        toGroup.children.append(reference)
        elements[fileAbsolutePath] = file
    }

    /// Returns the group at the given path if it's been added to the file elements object.
    ///
    /// - Parameter path: absolute path.
    /// - Returns: the group if it exists.
    func group(path: AbsolutePath) -> PBXGroup? {
        return elements[path] as? PBXGroup
    }

    /// Returns the file reference of the product with the given name.
    ///
    /// - Parameter name: Product name.
    /// - Returns: product file reference.
    func product(name: String) -> PBXFileReference? {
        return products[name]
    }

    /// Returns the file at the given path if it's been added to the file elements object.
    ///
    /// - Parameter path: absolute path.
    /// - Returns: the file if it exists.
    func file(path: AbsolutePath) -> PBXFileReference? {
        return elements[path] as? PBXFileReference
    }

    /// Returns true if a path represents a localized resource *.lproj.
    ///
    /// - Parameter path: path to be checked.
    /// - Returns: true if the file is a localized file.
    func isLocalized(path: AbsolutePath) -> Bool {
        return path.extension == "lproj"
    }

    /// Returns true if the path is a version group.
    ///
    /// - Parameter path: path.
    /// - Returns: true if the path is a version group.
    func isVersionGroup(path: AbsolutePath) -> Bool {
        return path.extension == "xcdatamodeld"
    }

    /// Returns true if the path should be a group.
    ///
    /// - Parameter path: path.
    /// - Returns: true if the path should be represented as a group.
    func isGroup(path: AbsolutePath) -> Bool {
        return !isVersionGroup(path: path) && path.extension == nil
    }

    /// Normalizes a path. Some paths have no direct representation in Xcode,
    /// like localizable files. This method normalizes those and returns a project
    /// representable path.
    ///
    /// - Example:
    ///   /test/es.lproj/Main.storyboard ~> /test/es.lproj
    ///
    /// - Parameter path: path to be normalized.
    /// - Returns: normalized path.
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
    ///
    /// - Parameters:
    ///   - filePath: absolute file path.
    ///   - sourceRootPath: source root path.
    /// - Returns: the relative path.
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
