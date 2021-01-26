import Foundation
import TSCBasic
import TuistCore
import TuistGraph
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
        if target.resources.isEmpty && target.coreDataModels.isEmpty { return ([target], []) }
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
                                         infoPlist: .extendingDefault(with: [:]),
                                         resources: target.resources,
                                         copyFiles: target.copyFiles,
                                         coreDataModels: target.coreDataModels,
                                         filesGroup: target.filesGroup)
            modifiedTarget.resources = []
            modifiedTarget.copyFiles = []
            modifiedTarget.dependencies.append(.target(name: bundleName))
            additionalTargets.append(resourcesTarget)
        }

        if target.supportsSources {
            let (filePath, fileDescriptors) = synthesizedFile(bundleName: bundleName, target: target, project: project)
            modifiedTarget.sources.append(SourceFile(path: filePath, compilerFlags: nil))
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
                                                                 bundleName: bundleName,
                                                                 target: target)
        return (filePath, [.file(.init(path: filePath, contents: content.data(using: .utf8), state: .present))])
    }

    static func fileContent(targetName: String, bundleName: String, target: Target) -> String {
        if !target.supportsResources {
            return """
            // swiftlint:disable all
            // swiftformat:disable all
            import Foundation

            // MARK: - Swift Bundle Accessor

            private class BundleFinder {}

            extension Foundation.Bundle {
                /// Since \(targetName) is a \(target.product), the bundle for classes within this module can be used directly.
                static var module: Bundle = {
                    let bundleName = "\(bundleName)"

                    let candidates = [
                        Bundle.main.resourceURL,
                        Bundle(for: BundleFinder.self).resourceURL,
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

            // MARK: - Objective-C Bundle Accessor

            @objc
            public class \(targetName.camelized.uppercasingFirst)Resources: NSObject {
               @objc public class var bundle: Bundle {
                     return .module
               }
            }
            // swiftlint:enable all
            // swiftformat:enable all
            """
        } else {
            return """
            // swiftlint:disable all
            // swiftformat:disable all
            import Foundation

            // MARK: - Swift Bundle Accessor

            private class BundleFinder {}

            extension Foundation.Bundle {
                /// Since \(targetName) is a \(target.product), the bundle containing the resources is copied into the final product.
                static var module: Bundle = {
                    return Bundle(for: BundleFinder.self)
                }()
            }

            // MARK: - Objective-C Bundle Accessor

            @objc
            public class \(targetName.camelized.uppercasingFirst)Resources: NSObject {
               @objc public class var bundle: Bundle {
                     return .module
               }
            }
            // swiftlint:enable all
            // swiftformat:enable all
            """
        }
    }
}
