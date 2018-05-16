import Basic
import Foundation
import xcodeproj

/// Object that contains references to the project base groups.
class ProjectGroups {
    /// Project main group.
    let main: PBXGroup

    /// Project products group.
    let products: PBXGroup

    /// Project support group.
    let support: PBXGroup

    /// Project project description group.
    let projectDescription: PBXGroup

    /// Files group.
    let files: PBXGroup

    /// Frameworks group.
    let frameworks: PBXGroup

    /// Project objects.
    let objects: PBXObjects

    /// Project configurations group.
    let configurations: PBXGroup

    /// Initializes the project groups with its attributes.
    ///
    /// - Parameters:
    ///   - main: main group.
    ///   - products: products group.
    ///   - configurations: configurations group.
    ///   - support: support group.
    ///   - files: files group.
    ///   - projectDescription: project description group.
    ///   - frameworks: frameworks group.
    ///   - objects: project objects.objects
    init(main: PBXGroup,
         products: PBXGroup,
         configurations: PBXGroup,
         support: PBXGroup,
         files: PBXGroup,
         projectDescription: PBXGroup,
         frameworks: PBXGroup,
         objects: PBXObjects) {
        self.main = main
        self.products = products
        self.support = support
        self.files = files
        self.configurations = configurations
        self.projectDescription = projectDescription
        self.frameworks = frameworks
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

    /// Returns a group that should contain all the configurations of a given target.
    ///
    /// - Parameter target: target name.
    /// - Returns: group to be used.
    /// - Throws: an error if the creation fails.
    func targetConfigurations(_ target: String) throws -> PBXGroup {
        if let group = configurations.group(named: target) {
            return group
        } else {
            return try configurations.addGroup(named: target, options: .withoutFolder).last!
        }
    }

    /// Returns a group that should contain all the configurations of a project.
    ///
    /// - Returns: the group to be used.
    /// - Throws: an error if the creation fails.
    func projectConfigurations() throws -> PBXGroup {
        if let group = configurations.group(named: "Project") {
            return group
        } else {
            return try configurations.addGroup(named: "Project", options: .withoutFolder).last!
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
        let mainGroup = PBXGroup(children: [],
                                 sourceTree: .group,
                                 path: project.path.relative(to: sourceRootPath).asString)
        objects.addObject(mainGroup)

        /// Files
        let filesGroup = PBXGroup(children: [], sourceTree: .group, name: "Files")
        let filesGroupReference = objects.addObject(filesGroup)
        mainGroup.children.append(filesGroupReference)

        /// Configurations
        let configurationsGroup = PBXGroup(children: [], sourceTree: .group, name: "Configurations")
        let configurationsGroupReference = objects.addObject(configurationsGroup)
        mainGroup.children.append(configurationsGroupReference)

        /// Support
        let supportGroup = PBXGroup(children: [], sourceTree: .group, name: "Support")
        let supportGroupReference = objects.addObject(supportGroup)
        mainGroup.children.append(supportGroupReference)

        /// ProjectDescription
        let projectDescriptionGroup = PBXGroup(children: [], sourceTree: .group, name: "ProjectDescription")
        let projectDescriptionGroupReference = objects.addObject(projectDescriptionGroup)
        mainGroup.children.append(projectDescriptionGroupReference)

        /// Frameworks
        let frameworksGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
        let frameworksGroupReference = objects.addObject(frameworksGroup)
        mainGroup.children.append(frameworksGroupReference)

        /// Products
        let productsGroup = PBXGroup(children: [], sourceTree: .buildProductsDir, name: "Products")
        let productsGroupReference = objects.addObject(productsGroup)
        mainGroup.children.append(productsGroupReference)

        return ProjectGroups(main: mainGroup,
                             products: productsGroup,
                             configurations: configurationsGroup,
                             support: supportGroup,
                             files: filesGroup,
                             projectDescription: projectDescriptionGroup,
                             frameworks: frameworksGroup,
                             objects: objects)
    }
}
