import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// A project mapper that adds support for defining resources in targets that don't support it
public class ResourcesProjectMapper: ProjectMapping {
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

        if !target.supportsResources {
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

    func synthesizedFile(bundleName: String, target: Target, project: Project) -> (AbsolutePath, [SideEffectDescriptor]) {
        let filePath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
            .appending(component: "Bundle+\(target.name).swift")

        let content: String = ResourcesProjectMapper.fileContent(targetName: target.name,
                                                                 bundleName: bundleName)
        return (filePath, [.file(.init(path: filePath, contents: content.data(using: .utf8), state: .present))])
    }

    static func fileContent(targetName: String, bundleName: String) -> String {
        """
        import class Foundation.Bundle

        private class BundleFinder {}

        extension Foundation.Bundle {
            /// Returns the resource bundle associated with the current Swift module.
            static var \(targetName.camelized.lowercasingFirst): Bundle = {
                let bundleName = "\(bundleName)"

                let candidates = [
                    // Bundle should be present here when the package is linked into an App.
                    Bundle.main.resourceURL,

                    // Bundle should be present here when the package is linked into a framework.
                    Bundle(for: BundleFinder.self).resourceURL,

                    // For command-line tools.
                    Bundle.main.bundleURL,
                ]

                for candidate in candidates {
                    let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
                    if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                        return bundle
                    }
                }
                fatalError("unable to find bundle named \(bundleName)")
            }()
        }
        """
    }
}
