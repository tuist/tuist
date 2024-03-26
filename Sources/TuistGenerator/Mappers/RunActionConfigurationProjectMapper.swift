import TuistCore
import TuistGraph
import XcodeProj

/// Mapper to preserve some options between `generate` runs that are considered ephemeral and specific to the current user, such as whether to use and which path to use for a custom working directory.
public final class RunActionConfigurationProjectMapper: ProjectMapping {
    public init() {}
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger
            .debug(
                "Transforming project \(project.name): Configuring run action with previous user options"
            )

        var project = project
        
        let previousXcodeProj = try? XcodeProj(pathString: project.xcodeProjPath.pathString)
        
        return (
            project
                .with(
                    schemes: project.schemes.map {
                        var scheme = $0
                        guard
                            let previousScheme = previousXcodeProj?.sharedData?.schemes
                                .first(where: { $0.name == scheme.name })
                            else
                        guard var runAction = scheme.runAction else { return $0 }
                        runAction.executable = nil
                        let launchArguments =
                        if var arguments = runAction.arguments, arguments.launchArguments.isEmpty {
                            arguments.launchArguments =
                        }
//                        if runAction.arguments?.launchArguments.isEmpty {
//                            runAction.arguments = Arguments(
//                                
//                            )
////                            previousScheme?.launchAction?.commandlineArguments?.arguments ?? []
//                        }
                        let launchArguments .launchArguments.isEmpty {
                            previousScheme?.launchAction?.commandlineArguments?.arguments ?? []
                        } else {
                            getCommandlineArguments(arguments.launchArguments)
                        }
                    }
                ),
            []
        )

        return (project, [])
    }
}
