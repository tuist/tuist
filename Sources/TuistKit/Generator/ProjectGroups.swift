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

    private let pbxproj: PBXProj
    private let projectGroups: [String: PBXGroup]
    private let allPredefinedGroups: OrderedSet<PBXGroup>

    // MARK: - Init

    private init(main: PBXGroup,
                 projectGroups: [(name: String, group: PBXGroup)],
                 products: PBXGroup,
                 projectManifest: PBXGroup,
                 frameworks: PBXGroup,
                 playgrounds: PBXGroup?,
                 pbxproj: PBXProj) {
        self.main = main
        self.projectGroups = Dictionary(uniqueKeysWithValues: projectGroups)
        self.products = products
        self.projectManifest = projectManifest
        self.frameworks = frameworks
        self.playgrounds = playgrounds
        self.pbxproj = pbxproj

        let allProjectGroups = projectGroups.map { $0.group }
        let predefinedGroups = [projectManifest, frameworks, playgrounds, products].compactMap { $0 }
        allPredefinedGroups = OrderedSet(allProjectGroups + predefinedGroups)
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

    /// Sorts groups in the following order
    ///
    /// - Any additional groups or files added to the main group directly
    /// - Project specified groups
    /// - Target specified groups (in the order the targets are defined)
    /// - Remaining predefined groups (e.g. Frameworks, Products etc...)
    ///
    func sort() {
        var additionalElements = main.children.filter {
            if let group = $0 as? PBXGroup {
                return !allPredefinedGroups.contains(group)
            }
            return true
        }

        additionalElements.sort(by: PBXFileElement.filesBeforeGroupsSort)

        main.children = additionalElements + Array(allPredefinedGroups)
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
        let projectGroupNames = [project.projectStructure.filesGroup] + targetGroups
        let groupsToCreate = OrderedSet(projectGroupNames.compactMap { $0 })
        var projectGroups = [(name: String, group: PBXGroup)]()
        groupsToCreate.forEach {
            let projectGroup = PBXGroup(children: [], sourceTree: .group, name: $0)
            pbxproj.add(object: projectGroup)
            mainGroup.children.append(projectGroup)
            projectGroups.append(($0, projectGroup))
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
                             projectGroups: projectGroups,
                             products: productsGroup,
                             projectManifest: projectManifestGroup,
                             frameworks: frameworksGroup,
                             playgrounds: playgroundsGroup,
                             pbxproj: pbxproj)
    }
}
