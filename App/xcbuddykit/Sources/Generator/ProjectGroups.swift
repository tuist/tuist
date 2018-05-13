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

    /// Targets group.
    let targets: PBXGroup

    /// Frameworks group.
    let frameworks: PBXGroup

    /// PBXProj instance.
    let pbxproj: PBXProj

    /// Project configurations group.
    let configurations: PBXGroup

    /// Initializes the object with the group.
    ///
    /// - Parameters:
    ///   - main: main group.
    ///   - products: products group.
    ///   - configurations: configurations group.
    ///   - support: support group.
    ///   - targets: targets group.
    ///   - projectDescription: project description group.
    init(main: PBXGroup,
         products: PBXGroup,
         configurations: PBXGroup,
         support: PBXGroup,
         targets: PBXGroup,
         projectDescription: PBXGroup,
         frameworks: PBXGroup,
         pbxproj: PBXProj) {
        self.main = main
        self.products = products
        self.support = support
        self.targets = targets
        self.configurations = configurations
        self.projectDescription = projectDescription
        self.frameworks = frameworks
        self.pbxproj = pbxproj
    }

    /// Returns a group that should contain all the target build files (sources & resources)
    ///
    /// - Parameter name: target name.
    /// - Returns: group to be used.
    /// - Throws: an error if the creation fails.
    func target(name: String) throws -> PBXGroup {
        if let group = targets.group(named: name) {
            return group
        } else {
            return try targets.addGroup(named: name, options: .withoutFolder).last!
        }
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
    ///   - pbxproj: PBXProj instance.
    ///   - sourceRootPath: path to the folder where the Xcode project is getting created.
    /// - Returns: project groups instance.
    static func generate(project: Project,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) -> ProjectGroups {
        /// Main
        let mainGroup = PBXGroup(children: [],
                                 sourceTree: .group,
                                 path: project.path.relative(to: sourceRootPath).asString)
        pbxproj.objects.addObject(mainGroup)

        /// Targets
        let targetsGroup = PBXGroup(children: [], sourceTree: .group, name: "Targets")
        let targetsGroupReference = pbxproj.objects.addObject(targetsGroup)
        mainGroup.children.append(targetsGroupReference)

        /// Configurations
        let configurationsGroup = PBXGroup(children: [], sourceTree: .group, name: "Configurations")
        let configurationsGroupReference = pbxproj.objects.addObject(configurationsGroup)
        mainGroup.children.append(configurationsGroupReference)

        /// Support
        let supportGroup = PBXGroup(children: [], sourceTree: .group, name: "Support")
        let supportGroupReference = pbxproj.objects.addObject(supportGroup)
        mainGroup.children.append(supportGroupReference)

        /// ProjectDescription
        let projectDescriptionGroup = PBXGroup(children: [], sourceTree: .group, name: "ProjectDescription")
        let projectDescriptionGroupReference = pbxproj.objects.addObject(projectDescriptionGroup)
        mainGroup.children.append(projectDescriptionGroupReference)

        /// Frameworks
        let frameworksGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
        let frameworksGroupReference = pbxproj.objects.addObject(frameworksGroup)
        mainGroup.children.append(frameworksGroupReference)

        /// Products
        let productsGroup = PBXGroup(children: [], sourceTree: .buildProductsDir, name: "Products")
        let productsGroupReference = pbxproj.objects.addObject(productsGroup)
        mainGroup.children.append(productsGroupReference)

        return ProjectGroups(main: mainGroup,
                             products: productsGroup,
                             configurations: configurationsGroup,
                             support: supportGroup,
                             targets: targetsGroup,
                             projectDescription: projectDescriptionGroup,
                             frameworks: frameworksGroup,
                             pbxproj: pbxproj)
    }
}
