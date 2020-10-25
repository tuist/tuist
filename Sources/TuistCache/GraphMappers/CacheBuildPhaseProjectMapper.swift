import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public class CacheBuildPhaseProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let project = project.with(targets: project.targets.map { target in
            var target = target
            if target.product.isFramework {
                target.scripts.append(.init(name: "[Tuist] Create file to locate the built products directory",
                                            script: script(target: target),
                                            showEnvVarsInLog: true,
                                            hashable: false))
            }
            return target
        })
        return (project, [])
    }

    fileprivate func script(target: Target) -> String {
        """
        if [ -n "$\(target.targetLocatorBuildPhaseVariable)" ]; then
            touch $BUILT_PRODUCTS_DIR/.$\(target.targetLocatorBuildPhaseVariable).tuist
        fi
        """
    }
}
