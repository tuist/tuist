import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

/// A project mapper that generates derived modulemap for targets which:
/// - don't define a modulemap
/// - contain a single header with a name different from the target name.
public final class GenerateModuleMapProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let moduleMapsDirectoryName: String

    public init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        moduleMapsDirectoryName: String = Constants.DerivedDirectory.moduleMaps
    ) {
        self.derivedDirectoryName = derivedDirectoryName
        self.moduleMapsDirectoryName = moduleMapsDirectoryName
    }

    // MARK: - ProjectMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let results = try project.targets.reduce(into: (targets: [Target](), sideEffects: [SideEffectDescriptor]())) { results, target in
            let (updatedTarget, sideEffects) = try map(target: target, project: project)
            results.targets.append(updatedTarget)
            results.sideEffects.append(contentsOf: sideEffects)
        }

        return (project.with(targets: results.targets), results.sideEffects)
    }

    // MARK: - Private

    private func map(target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        let moduleMapSetting = "MODULEMAP_FILE"

        guard target.settings?.base[moduleMapSetting] == nil else {
            // Module map manually defined, nothing to do
            return (target, [])
        }

        let publicHeadersCount = target.headers?.public.count ?? 0
        guard publicHeadersCount == 1 else {
            // No header or multiple headers, nothing to do
            return (target, [])
        }

        guard
            let header = target.headers?.public.first,
            header.basenameWithoutExt != target.name
        else {
            // Header with same name of target, nothing to do
            return (target, [])
        }

        let data = """
        framework module \(target.name) {
            umbrella header "\(header.basename)"
            export *
            module * { export * }
        }
        """.data(using: .utf8)

        let moduleMapPath = project.path
            .appending(component: derivedDirectoryName)
            .appending(component: moduleMapsDirectoryName)
            .appending(component: "\(target.name).modulemap")

        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: moduleMapPath, contents: data))

        let newTarget = target.with(additionalSettings: [moduleMapSetting: .string(moduleMapPath.relative(to: project.path).pathString)])

        return (newTarget, [sideEffect])
    }
}
