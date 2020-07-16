import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// A project mapper that adds support for defining resources in  libraries
public class LibraryResourcesProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var sideEffects: [SideEffectDescriptor] = []
        var targets: [Target] = []

        project.targets.forEach { target in
            let (mappedTargets, targetSideEffects) = mapTarget(target, project: project)
            targets.append(contentsOf: mappedTargets)
            sideEffects.append(contentsOf: targetSideEffects)
        }

        return (project.with(targets: targets), sideEffects)
    }

    public func mapTarget(_ target: Target, project: Project) -> ([Target], [SideEffectDescriptor]) {
        guard target.resources.count != 0 else { return ([target], []) }
        var additionalTargets: [Target] = []
        var sideEffects: [SideEffectDescriptor] = []

        let bundleName = "\(target.name)Resources"
        var modifiedTarget = target

        if target.product.isStatic {
            let resourcesTarget = Target(name: bundleName,
                                         platform: target.platform,
                                         product: .bundle,
                                         productName: nil,
                                         bundleId: "\(target.bundleId).resources",
                                         resources: target.resources,
                                         filesGroup: target.filesGroup)
            modifiedTarget.resources = []
            modifiedTarget.dependencies.append(.target(name: bundleName))
            additionalTargets.append(resourcesTarget)
        }

        if target.supportsSources {
            let (filePath, fileDescriptors) = synthesizedFile(bundleName: bundleName, target: target, project: project)
            modifiedTarget.sources.append((path: filePath, compilerFlags: nil))
            sideEffects.append(contentsOf: fileDescriptors)
        }

        return ([modifiedTarget] + additionalTargets, sideEffects)
    }

    public func synthesizedFile(bundleName: String, target: Target, project: Project) -> (AbsolutePath, [SideEffectDescriptor]) {
        let filePath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "Bundle+\(target.name).swift")

        let content: String

        // The bundle is copied into the final product's bundle
        if target.product.isStatic {
            content = """
            import Foundation

            public extension Bundle {
                static var \(target.name.camelized.lowercasingFirst): Bundle {
                    return Bundle(url: Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle"))!
                }
            }
            """
        } else {
            content = """
            import Foundation

            private class \(target.name.camelized.uppercasingFirst)Bundle {}

            public extension Bundle {
                static var \(target.name.camelized.lowercasingFirst): Bundle {
                    return Bundle(for: \(target.name.camelized.uppercasingFirst)Bundle.self)
                }
            }
            """
        }

        return (filePath, [.file(.init(path: filePath, contents: content.data(using: .utf8), state: .present))])
    }
}
