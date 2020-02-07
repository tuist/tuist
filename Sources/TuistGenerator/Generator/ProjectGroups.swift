import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

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
    
    static func sortGroups(group: PBXGroup) {
        let children = group.children
            .sorted { (child1, child2) -> Bool in
            let sortOrder1 = child1.getSortOrder()
            let sortOrder2 = child2.getSortOrder()
            
            if sortOrder1 != sortOrder2 {
                return sortOrder1 < sortOrder2
            } else {
                if (child1.name, child1.path) != (child2.name, child2.path) {
                    return PBXFileElement.sortByNamePath(child1, child2)
                } else {
                    return child1.context ?? "" < child2.context ?? ""
                }
            }
        }
        
        group.children = children.filter { $0 != group }
        
        let childGroups = group.children.compactMap { $0 as? PBXGroup }
        childGroups.forEach(sortGroups)
    }

    static func generate(project: Project,
                         pbxproj: PBXProj,
                         xcodeprojPath: AbsolutePath,
                         sourceRootPath: AbsolutePath,
                         playgrounds: Playgrounding = Playgrounds()) -> ProjectGroups {
        /// Main
        let projectRelativePath = sourceRootPath.relative(to: xcodeprojPath.parentDirectory).pathString
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

        /// Playgrounds
        var playgroundsGroup: PBXGroup!
        if !playgrounds.paths(path: project.path).isEmpty {
            playgroundsGroup = PBXGroup(children: [], sourceTree: .group, path: "Playgrounds")
            pbxproj.add(object: playgroundsGroup)
        }

        /// Products
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        return ProjectGroups(main: mainGroup,
                             projectGroups: projectGroups,
                             products: productsGroup,
                             frameworks: frameworksGroup,
                             playgrounds: playgroundsGroup,
                             pbxproj: pbxproj)
    }
    
    static func addFirstLevelDefaults(firstLevelGroup: ProjectGroups) {
        firstLevelGroup.main.children.append(firstLevelGroup.frameworks)
        if let playgroundsGroup = firstLevelGroup.playgrounds {
            firstLevelGroup.main.children.append(playgroundsGroup)
        }
        firstLevelGroup.main.children.append(firstLevelGroup.products)
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

extension PBXFileElement {
    public func getSortOrder() -> Int {
        if type(of: self).isa == "PBXGroup" {
            return -1
        } else {
            return 0
        }
    }
    
    public static func sortByNamePath(_ lhs: PBXFileElement, _ rhs: PBXFileElement) -> Bool {
        return lhs.namePathSortString.localizedStandardCompare(rhs.namePathSortString) == .orderedAscending
    }
    
    private var namePathSortString: String {
        return "\(name ?? path ?? "")\t\(name ?? "")\t\(path ?? "")"
    }
}
