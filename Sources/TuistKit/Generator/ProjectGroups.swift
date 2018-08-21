import Basic
import Foundation
import xcodeproj

class ProjectGroups {

    // MARK: - Attributes

    let main: PBXGroup
    let products: PBXGroup
    let projectDescription: PBXGroup
    let project: PBXGroup
    let frameworks: PBXGroup
    let playgrounds: PBXGroup
    let objects: PBXObjects

    // MARK: - Init

    init(main: PBXGroup,
         products: PBXGroup,
         projectDescription: PBXGroup,
         frameworks: PBXGroup,
         project: PBXGroup,
         playgrounds: PBXGroup,
         objects: PBXObjects) {
        self.main = main
        self.products = products
        self.projectDescription = projectDescription
        self.frameworks = frameworks
        self.project = project
        self.playgrounds = playgrounds
        self.objects = objects
    }

    func targetFrameworks(target: String) throws -> PBXGroup {
        if let group = frameworks.group(named: target) {
            return group
        } else {
            return try frameworks.addGroup(named: target, options: .withoutFolder).last!
        }
    }

    static func generate(project: Project,
                         objects: PBXObjects,
                         sourceRootPath: AbsolutePath) -> ProjectGroups {
        /// Main
        let projectRelativePath = project.path.relative(to: sourceRootPath).asString
        let mainGroup = PBXGroup(childrenReferences: [],
                                 sourceTree: .group,
                                 path: (projectRelativePath != ".") ? projectRelativePath : nil)
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

        /// Playgrounds
        let playgroundsGroup = PBXGroup(childrenReferences: [], sourceTree: .group, path: "Playgrounds")
        let playgroundsGroupReference = objects.addObject(playgroundsGroup)
        mainGroup.childrenReferences.append(playgroundsGroupReference)

        /// Products
        let productsGroup = PBXGroup(childrenReferences: [], sourceTree: .group, name: "Products")
        let productsGroupReference = objects.addObject(productsGroup)
        mainGroup.childrenReferences.append(productsGroupReference)

        return ProjectGroups(main: mainGroup,
                             products: productsGroup,
                             projectDescription: projectDescriptionGroup,
                             frameworks: frameworksGroup,
                             project: projectGroup,
                             playgrounds: playgroundsGroup,
                             objects: objects)
    }
}
