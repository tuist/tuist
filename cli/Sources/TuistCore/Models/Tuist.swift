import Path
import TSCUtility
import TuistConfig

#if DEBUG
    extension TuistConfig.TuistGeneratedProjectOptions.GenerationOptions {
        public func withWorkspaceName(_ workspaceName: String) -> Self {
            var options = self
            if let clonedSourcePackagesDirPath {
                var workspaceName = workspaceName
                if workspaceName.hasSuffix(".xcworkspace") {
                    workspaceName = String(workspaceName.dropLast(".xcworkspace".count))
                }
                let mangledWorkspaceName = workspaceName.spm_mangledToC99ExtendedIdentifier()
                var additionalPackageResolutionArguments = options.additionalPackageResolutionArguments
                additionalPackageResolutionArguments.append(
                    contentsOf: [
                        "-clonedSourcePackagesDirPath",
                        clonedSourcePackagesDirPath.appending(component: mangledWorkspaceName).pathString,
                    ]
                )
                options.additionalPackageResolutionArguments = additionalPackageResolutionArguments
            }
            return options
        }
    }
#endif
