import Testing
@testable import XcodeProj

extension PBXProj {
    func add(objects: [PBXObject]) {
        objects.forEach { add(object: $0) }
    }
}

extension PBXObject {
    @discardableResult
    func add(to pbxProj: PBXProj) -> Self {
        pbxProj.add(object: self)

        return self
    }
}

extension PBXFileElement {
    @discardableResult
    func addToMainGroup(in pbxProj: PBXProj) throws -> Self {
        let project = try #require(pbxProj.projects.first)
        project.mainGroup.children.append(self)
        return self
    }
}

extension PBXTarget {
    @discardableResult
    func add(to pbxProject: PBXProject?) throws -> Self {
        let project = try #require(pbxProject)
        project.targets.append(self)
        return self
    }
}

extension PBXProj {
    /// Adds a PBXObject to the project and returns it.
    @discardableResult
    func addObject<T: PBXObject>(_ object: T) -> T {
        add(object: object)
        return object
    }

    /// Adds a PBXFileReference and optionally attaches it to the main group.
    @discardableResult
    func addFileReference(
        _ file: PBXFileReference,
        addToMainGroup: Bool = true
    ) -> PBXFileReference {
        addObject(file)

        if addToMainGroup, let project = projects.first,
           let mainGroup = project.mainGroup
        {
            mainGroup.children.append(file)
        }

        return file
    }
}
