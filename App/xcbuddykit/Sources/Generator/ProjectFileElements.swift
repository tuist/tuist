import Basic
import Foundation
import xcodeproj

class ProjectFileElements {
    /// Elements
    var elements: [AbsolutePath: PBXFileElement] = [:]

    /// Default constructor.
    init(_ elements: [AbsolutePath: PBXFileElement] = [:]) {
        self.elements = elements
    }

    /// Generates all the project files.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - groups: project groups.
    ///   - objects: project objects.
    ///   - sourceRootPath: source root path.
    func generateProjectFiles(project: Project,
                              groups: ProjectGroups,
                              objects: PBXObjects,
                              sourceRootPath: AbsolutePath) {
        var files = Set<AbsolutePath>()
        project.targets.forEach { target in
            files.formUnion(targetFiles(target: target))
        }
        files.formUnion(projectFiles(project: project))
        generate(files: files.sorted(),
                 groups: groups,
                 objects: objects,
                 sourceRootPath: sourceRootPath)
    }

    /// Returns the project files.
    ///
    /// - Parameter project: project.
    /// - Returns: project files.
    func projectFiles(project: Project) -> Set<AbsolutePath> {
        var files = Set<AbsolutePath>()
        if let debugConfigFile = project.settings?.debug?.xcconfig {
            files.insert(debugConfigFile)
        }
        if let releaseConfigFile = project.settings?.release?.xcconfig {
            files.insert(releaseConfigFile)
        }
        return files
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
            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
                files.formUnion(sourcesBuildPhase.buildFiles.files)
            } else if let resourcesBuildPhase = buildPhase as? ResourcesBuildPhase {
                files.formUnion(resourcesBuildPhase.buildFiles.files)
            } else if let headersBuildPhase = buildPhase as? HeadersBuildPhase {
                files.formUnion(headersBuildPhase.public.files)
                files.formUnion(headersBuildPhase.project.files)
                files.formUnion(headersBuildPhase.private.files)
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
        let firstElement = addComponent(relative: closestRelativeRelativePath, from: sourceRootPath, toGroup: groups.project, objects: objects)

        // If it matches the file that we are adding or it's not a group we can exit.
        if (closestRelativeAbsolutePath == path) || !(firstElement.element is PBXGroup) {
            return
        }

        // swiftlint:disable:next force_cast
        var lastGroup: PBXGroup! = firstElement.element as! PBXGroup
        var lastPath: AbsolutePath = firstElement.path

        path.relative(to: lastPath).components.forEach { component in
            if lastGroup == nil { return }
            let element = addComponent(relative: RelativePath(component),
                                       from: lastPath,
                                       toGroup: lastGroup!,
                                       objects: objects)
            lastGroup = element.element as? PBXGroup
            lastPath = element.path
        }
    }

    /// Returns the group at the given path if it's been added to the file elements object.
    ///
    /// - Parameter path: absolute path.
    /// - Returns: the group if it exists.
    func group(path: AbsolutePath) -> PBXGroup? {
        return elements[path] as? PBXGroup
    }

    /// Returns the file at the given path if it's been added to the file elements object.
    ///
    /// - Parameter path: absolute path.
    /// - Returns: the file if it exists.
    func file(path: AbsolutePath) -> PBXFileReference? {
        return elements[path] as? PBXFileReference
    }

    // MARK: - Fileprivate

    /// Adds a new file or group to an existing group.
    ///
    /// - Parameters:
    ///   - relative: relative path from the group that is passed.
    ///   - from: absolute path of the group that is passed.
    ///   - toGroup: group where the file/group should be added.
    ///   - objects: project objects.
    @discardableResult func addComponent(relative: RelativePath,
                                         from: AbsolutePath,
                                         toGroup: PBXGroup,
                                         objects: PBXObjects) -> (element: PBXFileElement, path: AbsolutePath) {
        let absolutePath = from.appending(relative)
        if elements[absolutePath] != nil {
            return (element: elements[absolutePath]!, path: from.appending(relative))
        }

        // If the path is ../../xx we specify the name
        // to prevent Xcode from using that as a name.
        var name: String?
        let components = relative.components
        if components.count != 1 {
            name = components.last!
        }

        // Folder
        if relative.extension == nil {
            let group = PBXGroup(children: [], sourceTree: .group, name: name, path: relative.asString)
            let reference = objects.addObject(group)
            toGroup.children.append(reference)
            elements[absolutePath] = group
            return (element: group, path: from.appending(relative))

            // File
        } else {
            let lastKnownFileType = Xcode.filetype(extension: absolutePath.extension!)
            let file = PBXFileReference(sourceTree: .group, name: name, lastKnownFileType: lastKnownFileType, path: relative.asString)
            let reference = objects.addObject(file)
            toGroup.children.append(reference)
            elements[absolutePath] = file
            return (element: file, path: from.appending(relative))
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
