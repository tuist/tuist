import Basic
import Foundation
import xcodeproj

/// Object that contains references to the project base groups.
class ProjectGroups {
    /// Project main group.
    let main: PBXGroup

    /// Project products group.
    let products: PBXGroup

    /// Project project description group.
    let projectDescription: PBXGroup

    /// Project group.
    let project: PBXGroup

    /// Frameworks group.
    let frameworks: PBXGroup

    /// Project objects.
    let objects: PBXObjects

    /// Initializes the project groups with its attributes.
    ///
    /// - Parameters:
    ///   - main: main group.
    ///   - products: products group.
    ///   - projectDescription: project description group.
    ///   - frameworks: frameworks group.
    ///   - project: project group.
    ///   - objects: project objects.objects
    init(main: PBXGroup,
         products: PBXGroup,
         projectDescription: PBXGroup,
         frameworks: PBXGroup,
         project: PBXGroup,
         objects: PBXObjects) {
        self.main = main
        self.products = products
        self.projectDescription = projectDescription
        self.frameworks = frameworks
        self.project = project
        self.objects = objects
    }

    /// Returns a group that should contain all the frameworks of a given target.
    ///
    /// - Parameter target: target name.
    /// - Returns: group to be used.
    /// - Throws: an error if the creation fails.
    func targetFrameworks(target: String) throws -> PBXGroup {
        if let group = frameworks.group(named: target) {
            return group
        } else {
            return try frameworks.addGroup(named: target, options: .withoutFolder).last!
        }
    }

    /// Generates all the Xcode project base groups and returns an instance of ProjectGroups
    /// that contains a reference to them.
    ///
    /// - Parameters:
    ///   - project: project spec.
    ///   - objects: project objects.
    ///   - sourceRootPath: path to the folder where the Xcode project is getting created.
    /// - Returns: project groups instance.
    static func generate(project: Project,
                         objects: PBXObjects,
                         sourceRootPath: AbsolutePath) -> ProjectGroups {
        /// Main
        let mainGroup = PBXGroup(childrenReferences: [],
                                 sourceTree: .group,
                                 path: project.path.relative(to: sourceRootPath).asString)
        objects.addObject(mainGroup)

        /// Project
        let projectGroup = PBXGroup(childrenReferences: [], sourceTree: .group, name: "Project")
        let projectGroupReference = objects.addObject(projectGroup)
        mainGroup.childrenReferences.append(projectGroupReference)

        /// ProjectDescription
        let projectDescriptionGroup = PBXGroup(childrenReferences: [], sourceTree: .group, name: "ProjectDescription")
        let projectDescriptionGroupReference = objects.addObject(projectDescriptionGroup)
        mainGroup.childrenReferences.append(projectDescriptionGroupReference)

        /// Frameworks
        let frameworksGroup = PBXGroup(childrenReferences: [], sourceTree: .group, name: "Frameworks")
        let frameworksGroupReference = objects.addObject(frameworksGroup)
        mainGroup.childrenReferences.append(frameworksGroupReference)

        /// Products
        let productsGroup = PBXGroup(childrenReferences: [], sourceTree: .group, name: "Products")
        let productsGroupReference = objects.addObject(productsGroup)
        mainGroup.childrenReferences.append(productsGroupReference)

        return ProjectGroups(main: mainGroup,
                             products: productsGroup,
                             projectDescription: projectDescriptionGroup,
                             frameworks: frameworksGroup,
                             project: projectGroup,
                             objects: objects)
    }
}
