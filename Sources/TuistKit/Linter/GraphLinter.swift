import Foundation
import TuistCore

protocol GraphLinting: AnyObject {
    func lint(graph: Graphing) -> [LintingIssue]
}

class GraphLinter: GraphLinting {
    // MARK: - Attributes

    let projectLinter: ProjectLinting
    let fileHandler: FileHandling

    // MARK: - Init

    init(projectLinter: ProjectLinting = ProjectLinter(),
         fileHandler: FileHandling = FileHandler()) {
        self.projectLinter = projectLinter
        self.fileHandler = fileHandler
    }

    // MARK: - GraphLinting

    func lint(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graph.projects.flatMap(projectLinter.lint))
        issues.append(contentsOf: lintDependencies(graph: graph))
        return issues
    }

    // MARK: - Fileprivate

    fileprivate func lintDependencies(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        var evaluatedNodes: [GraphNode] = []
        graph.entryNodes.forEach {
            issues.append(contentsOf: lintGraphNode(node: $0, evaluatedNodes: &evaluatedNodes))
        }

        issues.append(contentsOf: lintCarthageDependencies(graph: graph))

        return issues
    }

    fileprivate func lintCarthageDependencies(graph: Graphing) -> [LintingIssue] {
        let frameworks = graph.frameworks
        let carthageFrameworks = frameworks.filter({ $0.isCarthage })
        let nonCarthageFrameworks = frameworks.filter({ !$0.isCarthage })

        let carthageIssues = carthageFrameworks
            .filter({ !fileHandler.exists($0.path) })
            .map({ LintingIssue(reason: "Framework not found at path \($0.path.asString). The path might be wrong or Carthage dependencies not fetched", severity: .warning) })
        let nonCarthageIssues = nonCarthageFrameworks
            .filter({ !fileHandler.exists($0.path) })
            .map({ LintingIssue(reason: "Framework not found at path \($0.path.asString)", severity: .error) })

        var issues: [LintingIssue] = []
        issues.append(contentsOf: carthageIssues)
        issues.append(contentsOf: nonCarthageIssues)

        return issues
    }

    fileprivate func lintGraphNode(node: GraphNode, evaluatedNodes: inout [GraphNode]) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        defer { evaluatedNodes.append(node) }

        if evaluatedNodes.contains(node) { return issues }
        guard let targetNode = node as? TargetNode else { return issues }

        targetNode.dependencies.forEach { toNode in
            if let toTargetNode = toNode as? TargetNode {
                issues.append(contentsOf: lintDependency(from: targetNode, to: toTargetNode))
            }
            issues.append(contentsOf: lintGraphNode(node: toNode, evaluatedNodes: &evaluatedNodes))
        }

        return issues
    }

    fileprivate func lintDependency(from: TargetNode, to: TargetNode) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let fromTarget = LintableTarget(platform: from.target.platform,
                                        product: from.target.product)
        let toTarget = LintableTarget(platform: to.target.platform,
                                      product: to.target.product)

        if !GraphLinter.validLinks.keys.contains(fromTarget) {
            let reason = "Target \(from.target.name) has a platform '\(from.target.platform)' and product '\(from.target.product)' invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }
        let supportedTargets = GraphLinter.validLinks[fromTarget]!

        if !supportedTargets.contains(toTarget) {
            let reason = "Target \(from.target.name) has a dependency with target \(to.target.name) of type \(to.target.product) for platform '\(to.target.platform)' which is invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }

        return issues
    }

    struct LintableTarget: Equatable, Hashable {
        let platform: Platform
        let product: Product
    }

    static let validLinks: [LintableTarget: [LintableTarget]] = [
        // iOS products
        LintableTarget(platform: .iOS, product: .app): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
//            LintableTarget(platform: .iOS, product: .appExtension),
//            LintableTarget(platform: .iOS, product: .messagesExtension),
//            LintableTarget(platform: .iOS, product: .stickerPack),
//            LintableTarget(platform: .watchOS, product: .watch2App),
//            LintableTarget(platform: .watchOS, product: .watchApp),
        ],
        LintableTarget(platform: .iOS, product: .staticLibrary): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .iOS, product: .staticFramework): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .iOS, product: .dynamicLibrary): [
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
        ],
        LintableTarget(platform: .iOS, product: .framework): [
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .unitTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .iOS, product: .uiTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        //        LintableTarget(platform: .iOS, product: .appExtension): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
//        LintableTarget(platform: .iOS, product: .messagesApplication): [
//            LintableTarget(platform: .iOS, product: .messagesExtension),
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
//        LintableTarget(platform: .iOS, product: .messagesExtension): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
//        LintableTarget(platform: .iOS, product: .stickerPack): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
        // macOS
        LintableTarget(platform: .macOS, product: .app): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
//            LintableTarget(platform: .macOS, product: .appExtension),
        ],
        LintableTarget(platform: .macOS, product: .staticLibrary): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .staticFramework): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .dynamicLibrary): [
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
        ],
        LintableTarget(platform: .macOS, product: .framework): [
            LintableTarget(platform: .macOS, product: .framework),
        ],
        LintableTarget(platform: .macOS, product: .unitTests): [
            LintableTarget(platform: .macOS, product: .app),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .uiTests): [
            LintableTarget(platform: .macOS, product: .app),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        //        LintableTarget(platform: .macOS, product: .appExtension): [
//            LintableTarget(platform: .macOS, product: .staticLibrary),
//            LintableTarget(platform: .macOS, product: .dynamicLibrary),
//            LintableTarget(platform: .macOS, product: .framework),
//        ],
        // tvOS
        LintableTarget(platform: .tvOS, product: .app): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
//            LintableTarget(platform: .tvOS, product: .tvExtension),
        ],
        LintableTarget(platform: .tvOS, product: .staticLibrary): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .tvOS, product: .staticFramework): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .tvOS, product: .dynamicLibrary): [
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
        ],
        LintableTarget(platform: .tvOS, product: .framework): [
            LintableTarget(platform: .tvOS, product: .framework),
        ],
        LintableTarget(platform: .tvOS, product: .unitTests): [
            LintableTarget(platform: .tvOS, product: .app),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
//        LintableTarget(platform: .tvOS, product: .tvExtension): [
//            LintableTarget(platform: .tvOS, product: .staticLibrary),
//            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
//            LintableTarget(platform: .tvOS, product: .framework),
//        ],
        // watchOS
//        LintableTarget(platform: .watchOS, product: .watchApp): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//            LintableTarget(platform: .watchOS, product: .watchExtension),
//        ],
//        LintableTarget(platform: .watchOS, product: .watch2App): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//            LintableTarget(platform: .watchOS, product: .watch2Extension),
//        ],
//        LintableTarget(platform: .watchOS, product: .staticLibrary): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//        ],
//        LintableTarget(platform: .watchOS, product: .dynamicLibrary): [
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//        ],
//        LintableTarget(platform: .watchOS, product: .framework): [
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
//        LintableTarget(platform: .watchOS, product: .watchExtension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
//        LintableTarget(platform: .watchOS, product: .watch2Extension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
    ]
}
