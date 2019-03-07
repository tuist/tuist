import Basic
import Foundation
import TuistCore
import xcodeproj

enum ProjectGroupsError: FatalError, Equatable {
    case missingGroup(String)

    var description: String {
        switch self {
        case let .missingGroup(group):
            return "Couldn't find group: \(group)"
        }
    }

    var type: ErrorType {
        switch self {
        case .missingGroup:
            return .bug
        }
    }
}

class ProjectGroups {
    // MARK: - Attributes

    let main: PBXGroup
    let products: PBXGroup
    let projectManifest: PBXGroup
    let frameworks: PBXGroup
    let playgrounds: PBXGroup?
    let pbxproj: PBXProj

    // MARK: - Init

    init(main: PBXGroup,
         products: PBXGroup,
         projectManifest: PBXGroup,
         frameworks: PBXGroup,
         playgrounds: PBXGroup?,
         pbxproj: PBXProj) {
        self.main = main
        self.products = products
        self.projectManifest = projectManifest
        self.frameworks = frameworks
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

    func projectGroup(named name: String) throws -> PBXGroup {
        guard let group = main.group(named: name) else {
            throw ProjectGroupsError.missingGroup(name)
        }
        return group
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

        /// Project & Target Groups
        let targetGroups = project.targets.map { $0.projectStructure.filesGroup }
        let projectGroups = [project.projectStructure.filesGroup] + targetGroups
        let groupsToCreate = OrderedSet(projectGroups.compactMap { $0 })
        groupsToCreate.forEach {
            let projectGroup = PBXGroup(children: [], sourceTree: .group, name: $0)
            pbxproj.add(object: projectGroup)
            mainGroup.children.append(projectGroup)
        }

        /// ProjectDescription
        let projectManifestGroup = PBXGroup(children: [], sourceTree: .group, name: "Manifest")
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
                             playgrounds: playgroundsGroup,
                             pbxproj: pbxproj)
    }
}
