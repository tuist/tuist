import Basic
import Foundation
import xcodeproj

class ProjectGroups {
    // MARK: - Attributes

    let main: PBXGroup
    let products: PBXGroup
    let projectManifest: PBXGroup
    let project: PBXGroup
    let frameworks: PBXGroup
    let playgrounds: PBXGroup?
    let pbxproj: PBXProj

    // MARK: - Init

    init(main: PBXGroup,
         products: PBXGroup,
         projectManifest: PBXGroup,
         frameworks: PBXGroup,
         project: PBXGroup,
         playgrounds: PBXGroup?,
         pbxproj: PBXProj) {
        self.main = main
        self.products = products
        self.projectManifest = projectManifest
        self.frameworks = frameworks
        self.project = project
        self.playgrounds = playgrounds
        self.pbxproj = pbxproj
    }

    func targetFrameworks(target: String) throws -> PBXGroup {
        if let group = frameworks.group(named: target) {
            return group
        } else {
            return try frameworks.addGroup(named: target, options: .withoutFolder).last!
        }
    }

    static func generate(project: Project,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath,
                         playgrounds: Playgrounding = Playgrounds()) -> ProjectGroups {
        /// Main
        let projectRelativePath = project.path.relative(to: sourceRootPath).asString
        let mainGroup = PBXGroup(children: [],
                                 sourceTree: .group,
                                 path: (projectRelativePath != ".") ? projectRelativePath : nil)
        pbxproj.add(object: mainGroup)

        /// Project
        let projectGroup = PBXGroup(children: [], sourceTree: .group, name: "Project")
        pbxproj.add(object: projectGroup)
        mainGroup.children.append(projectGroup)

        /// ProjectDescription
        let projectManifestGroup = PBXGroup(children: [], sourceTree: .group, name: "ProjectManifest")
        pbxproj.add(object: projectManifestGroup)
        mainGroup.children.append(projectManifestGroup)

        /// Frameworks
        let frameworksGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
        pbxproj.add(object: frameworksGroup)
        mainGroup.children.append(frameworksGroup)

        /// Playgrounds
        var playgroundsGroup: PBXGroup!
        if !playgrounds.paths(path: project.path).isEmpty {
            playgroundsGroup = PBXGroup(children: [], sourceTree: .group, path: "Playgrounds")
            pbxproj.add(object: playgroundsGroup)
            mainGroup.children.append(playgroundsGroup)
        }

        /// Products
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)
        mainGroup.children.append(productsGroup)

        return ProjectGroups(main: mainGroup,
                             products: productsGroup,
                             projectManifest: projectManifestGroup,
                             frameworks: frameworksGroup,
                             project: projectGroup,
                             playgrounds: playgroundsGroup,
                             pbxproj: pbxproj)
    }
}
