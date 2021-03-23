import Foundation
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport

public protocol GraphLinting: AnyObject {
    func lint(graphTraverser: GraphTraversing) -> [LintingIssue]
}

// swiftlint:disable type_body_length
public class GraphLinter: GraphLinting {
    // MARK: - Attributes

    private let projectLinter: ProjectLinting
    private let staticProductsLinter: StaticProductsGraphLinting

    // MARK: - Init

    public convenience init() {
        let projectLinter = ProjectLinter()
        let staticProductsLinter = StaticProductsGraphLinter()
        self.init(
            projectLinter: projectLinter,
            staticProductsLinter: staticProductsLinter
        )
    }

    init(projectLinter: ProjectLinting,
         staticProductsLinter: StaticProductsGraphLinting)
    {
        self.projectLinter = projectLinter
        self.staticProductsLinter = staticProductsLinter
    }

    // MARK: - GraphLinting

    public func lint(graphTraverser: GraphTraversing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graphTraverser.projects.flatMap { project -> [LintingIssue] in
            projectLinter.lint(project.value)
        })
        issues.append(contentsOf: lintDependencies(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintMismatchingConfigurations(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintWatchBundleIndentifiers(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintBundleIdentifiers(graphTraverser: graphTraverser))

        return issues
    }

    // MARK: - Fileprivate

    func lintDependencies(graphTraverser: GraphTraversing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let dependencyIssues = graphTraverser.dependencies.flatMap { (fromDependency, toDependencies) -> [LintingIssue] in
            toDependencies.flatMap { (toDependency) -> [LintingIssue] in
                guard case let ValueGraphDependency.target(fromTargetName, fromTargetPath) = fromDependency else { return [] }
                guard case let ValueGraphDependency.target(toTargetName, toTargetPath) = toDependency else { return [] }
                guard let fromTarget = graphTraverser.target(path: fromTargetPath, name: fromTargetName) else { return [] }
                guard let toTarget = graphTraverser.target(path: toTargetPath, name: toTargetName) else { return [] }
                return lintDependency(from: fromTarget, to: toTarget)
            }
        }

        issues.append(contentsOf: dependencyIssues)
        issues.append(contentsOf: staticProductsLinter.lint(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintPrecompiledFrameworkDependencies(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintPackageDependencies(graphTraverser: graphTraverser))
        issues.append(contentsOf: lintAppClip(graphTraverser: graphTraverser))

        return issues
    }

    private func lintDependency(from: ValueGraphTarget, to: ValueGraphTarget) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let fromTarget = LintableTarget(
            platform: from.target.platform,
            product: from.target.product
        )
        let toTarget = LintableTarget(
            platform: to.target.platform,
            product: to.target.product
        )

        if !GraphLinter.validLinks.keys.contains(fromTarget) {
            let reason = "Target \(from.target.name) has a platform '\(from.target.platform)' and product '\(from.target.product)' invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }
        let supportedTargets = GraphLinter.validLinks[fromTarget]

        if supportedTargets == nil || supportedTargets?.contains(toTarget) == false {
            let reason = "Target \(from.target.name) has a dependency with target \(to.target.name) of type \(to.target.product) for platform '\(to.target.platform)' which is invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }

        return issues
    }

    private func lintMismatchingConfigurations(graphTraverser: GraphTraversing) -> [LintingIssue] {
        let rootProjects = graphTraverser.rootProjects()

        let knownConfigurations = rootProjects.reduce(into: Set()) {
            $0.formUnion(Set($1.settings.configurations.keys))
        }

        let projectBuildConfigurations = graphTraverser.projects.compactMap { project -> (name: String, buildConfigurations: Set<BuildConfiguration>)? in
            (name: project.value.name, buildConfigurations: Set(project.value.settings.configurations.keys))
        }

        let mismatchingBuildConfigurations = projectBuildConfigurations.filter {
            !knownConfigurations.isSubset(of: $0.buildConfigurations)
        }

        return mismatchingBuildConfigurations.map {
            let expectedConfigurations = knownConfigurations.sorted()
            let configurations = $0.buildConfigurations.sorted()
            let reason = "The project '\($0.name)' has missing or mismatching configurations. It has \(configurations), other projects have \(expectedConfigurations)"
            return LintingIssue(
                reason: reason,
                severity: .warning
            )
        }
    }

    /// It verifies setup for packages
    ///
    /// - Parameter graph: Project graph.
    /// - Returns: Linting issues.
    private func lintPackageDependencies(graphTraverser: GraphTraversing) -> [LintingIssue] {
        guard graphTraverser.hasPackages else { return [] }

        let version: Version
        do {
            version = try XcodeController.shared.selectedVersion()
        } catch {
            return [LintingIssue(reason: "Could not determine Xcode version", severity: .error)]
        }

        if version.major < 11 {
            let reason = "The project contains package dependencies but the selected version of Xcode is not compatible. Need at least 11 but got \(version)"
            return [LintingIssue(reason: reason, severity: .error)]
        }

        return []
    }

    private func lintAppClip(graphTraverser: GraphTraversing) -> [LintingIssue] {
        let apps = graphTraverser.apps()

        let issues = apps.flatMap { app -> [LintingIssue] in
            let appClips = graphTraverser.directLocalTargetDependencies(path: app.path, name: app.target.name)
                .filter { $0.target.product == .appClip }

            if appClips.count > 1 {
                return [
                    LintingIssue(
                        reason: "\(app) cannot depend on more than one app clip: \(appClips.map(\.target.name).sorted().listed())",
                        severity: .error
                    ),
                ]
            }

            return appClips.flatMap { appClip -> [LintingIssue] in
                lint(appClip: appClip, parentApp: app)
            }
        }

        return issues
    }

    private func lintPrecompiledFrameworkDependencies(graphTraverser: GraphTraversing) -> [LintingIssue] {
        let frameworks = graphTraverser.precompiledFrameworksPaths()

        return frameworks
            .filter { !FileHandler.shared.exists($0) }
            .map { LintingIssue(reason: "Framework not found at path \($0.pathString)", severity: .error) }
    }

    private func lintWatchBundleIndentifiers(graphTraverser: GraphTraversing) -> [LintingIssue] {
        let apps = graphTraverser.apps()

        let issues = apps.flatMap { app -> [LintingIssue] in
            let watchApps = graphTraverser.directLocalTargetDependencies(path: app.path, name: app.target.name)
                .filter { $0.target.product == .watch2App }

            return watchApps.flatMap { watchApp -> [LintingIssue] in
                let watchAppIssues = lint(watchApp: watchApp, parentApp: app)
                let watchExtensions = graphTraverser.directLocalTargetDependencies(path: watchApp.path, name: watchApp.target.name)
                    .filter { $0.target.product == .watch2Extension }

                let watchExtensionIssues = watchExtensions.flatMap { watchExtension in
                    lint(watchExtension: watchExtension, parentWatchApp: watchApp)
                }
                return watchAppIssues + watchExtensionIssues
            }
        }

        return issues
    }

    private func lint(watchApp: ValueGraphTarget, parentApp: ValueGraphTarget) -> [LintingIssue] {
        guard watchApp.target.bundleId.hasPrefix(parentApp.target.bundleId) else {
            return [
                LintingIssue(reason: """
                Watch app '\(watchApp.target.name)' bundleId: \(watchApp.target.bundleId) isn't prefixed with its parent's app '\(parentApp.target.bundleId)' bundleId '\(parentApp.target.bundleId)'
                """, severity: .error),
            ]
        }
        return []
    }

    private func lint(watchExtension: ValueGraphTarget, parentWatchApp: ValueGraphTarget) -> [LintingIssue] {
        guard watchExtension.target.bundleId.hasPrefix(parentWatchApp.target.bundleId) else {
            return [
                LintingIssue(reason: """
                Watch extension '\(watchExtension.target.name)' bundleId: \(watchExtension.target.bundleId) isn't prefixed with its parent's watch app '\(parentWatchApp.target.bundleId)' bundleId '\(parentWatchApp.target.bundleId)'
                """, severity: .error),
            ]
        }
        return []
    }

    private func lint(appClip: ValueGraphTarget, parentApp: ValueGraphTarget) -> [LintingIssue] {
        var foundIssues = [LintingIssue]()

        if !appClip.target.bundleId.hasPrefix(parentApp.target.bundleId) {
            foundIssues.append(
                LintingIssue(reason: """
                AppClip '\(appClip.target.name)' bundleId: \(appClip.target.bundleId) isn't prefixed with its parent's app '\(parentApp.target.name)' bundleId '\(parentApp.target.bundleId)'
                """, severity: .error))
        }

        if let entitlements = appClip.target.entitlements {
            if !FileHandler.shared.exists(entitlements) {
                foundIssues.append(LintingIssue(reason: "The entitlements at path '\(entitlements)' referenced by target does not exist", severity: .error))
            }
        } else {
            foundIssues.append(LintingIssue(reason: "An AppClip '\(appClip.target.name)' requires its Parent Application Identifiers Entitlement to be set", severity: .error))
        }

        return foundIssues
    }

    private struct BundleIdKey: Hashable {
        let bundleId: String
        let platform: Platform
    }

    private func lintBundleIdentifiers(graphTraverser: GraphTraversing) -> [LintingIssue] {
        var bundleIds = [BundleIdKey: [String]]()
        let buildSettingRegex = "\\$[\\({](.*)[\\)}]"

        graphTraverser.targets
            .flatMap { $0.value.map(\.value) }
            .forEach { target in
                if target.bundleId.matches(pattern: buildSettingRegex) {
                    return
                }

                let key = BundleIdKey(bundleId: target.bundleId, platform: target.platform)

                var targetsWithThisBundleId = bundleIds[key] ?? []
                targetsWithThisBundleId.append(target.name)
                bundleIds[key] = targetsWithThisBundleId
            }

        return duplicateBundleIdLintingIssue(for: bundleIds)
    }

    private func duplicateBundleIdLintingIssue(for targets: [BundleIdKey: [String]]) -> [LintingIssue] {
        targets.compactMap { bundleIdKey, targetNames in
            guard targetNames.count > 1 else {
                return nil
            }

            let reason = "The bundle identifier '\(bundleIdKey.bundleId)' is being used by multiple targets: \(targetNames.sorted().listed())."
            return LintingIssue(reason: reason, severity: .warning)
        }.sorted(by: { $0.reason < $1.reason })
    }

    struct LintableTarget: Equatable, Hashable {
        let platform: TuistGraph.Platform
        let product: Product
    }

    static let validLinks: [LintableTarget: [LintableTarget]] = [
        // iOS products
        LintableTarget(platform: .iOS, product: .app): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
            LintableTarget(platform: .iOS, product: .appExtension),
            LintableTarget(platform: .iOS, product: .messagesExtension),
            LintableTarget(platform: .iOS, product: .stickerPackExtension),
            LintableTarget(platform: .watchOS, product: .watch2App),
            LintableTarget(platform: .iOS, product: .appClip),
//            LintableTarget(platform: .watchOS, product: .watchApp),
        ],
        LintableTarget(platform: .iOS, product: .staticLibrary): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .staticFramework): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .dynamicLibrary): [
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .framework): [
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .unitTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
            LintableTarget(platform: .iOS, product: .appClip),
        ],
        LintableTarget(platform: .iOS, product: .uiTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
            LintableTarget(platform: .iOS, product: .appClip),
        ],
        LintableTarget(platform: .iOS, product: .appExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .appClip): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        //        LintableTarget(platform: .iOS, product: .messagesApplication): [
//            LintableTarget(platform: .iOS, product: .messagesExtension),
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
        LintableTarget(platform: .iOS, product: .messagesExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .stickerPackExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        // macOS
        LintableTarget(platform: .macOS, product: .app): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .appExtension),
        ],
        LintableTarget(platform: .macOS, product: .staticLibrary): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .staticFramework): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .dynamicLibrary): [
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .framework): [
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .bundle),
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
        LintableTarget(platform: .macOS, product: .appExtension): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
        ],
        LintableTarget(platform: .macOS, product: .commandLineTool): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
        ],
        // tvOS
        LintableTarget(platform: .tvOS, product: .app): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
//            LintableTarget(platform: .tvOS, product: .tvExtension),
        ],
        LintableTarget(platform: .tvOS, product: .staticLibrary): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .staticFramework): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .dynamicLibrary): [
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .framework): [
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .unitTests): [
            LintableTarget(platform: .tvOS, product: .app),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticFramework),
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
        LintableTarget(platform: .watchOS, product: .watch2App): [
            LintableTarget(platform: .watchOS, product: .watch2Extension),
        ],
        LintableTarget(platform: .watchOS, product: .staticLibrary): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .staticFramework): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .dynamicLibrary): [
            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .framework): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        //        LintableTarget(platform: .watchOS, product: .watchExtension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
        LintableTarget(platform: .watchOS, product: .watch2Extension): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .staticFramework),
        ],
    ]
}
