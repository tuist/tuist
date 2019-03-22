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
    let frameworks: PBXGroup
    let playgrounds: PBXGroup?

    private let pbxproj: PBXProj
    private let projectGroups: [String: PBXGroup]

    // MARK: - Init

    private init(main: PBXGroup,
                 projectGroups: [(name: String, group: PBXGroup)],
                 products: PBXGroup,
                 frameworks: PBXGroup,
                 playgrounds: PBXGroup?,
                 pbxproj: PBXProj) {
        self.main = main
        self.projectGroups = Dictionary(uniqueKeysWithValues: projectGroups)
        self.products = products
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
        guard let group = projectGroups[name] else {
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
        let projectGroupNames = extractProjectGroupNames(from: project)
        let groupsToCreate = OrderedSet(projectGroupNames)
        var projectGroups = [(name: String, group: PBXGroup)]()
        groupsToCreate.forEach {
            let projectGroup = PBXGroup(children: [], sourceTree: .group, name: $0)
            pbxproj.add(object: projectGroup)
            mainGroup.children.append(projectGroup)
            projectGroups.append(($0, projectGroup))
        }

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
                             projectGroups: projectGroups,
                             products: productsGroup,
                             frameworks: frameworksGroup,
                             playgrounds: playgroundsGroup,
                             pbxproj: pbxproj)
    }

    private static func extractProjectGroupNames(from project: Project) -> [String] {
        let groups = [project.filesGroup] + project.targets.map { $0.filesGroup }
        let groupNames: [String] = groups.compactMap {
            switch $0 {
            case let .group(name: groupName):
                return groupName
            }
        }
        return groupNames
    }
}
