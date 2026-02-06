import Path
import TSCUtility
import TuistConfig

public typealias Tuist = TuistConfig.Tuist
public typealias TuistConfigError = TuistConfig.TuistConfigError
public typealias InspectOptions = TuistConfig.InspectOptions
public typealias TuistProject = TuistConfig.TuistProject
public typealias TuistGeneratedProjectOptions = TuistConfig.TuistGeneratedProjectOptions
public typealias TuistXcodeProjectOptions = TuistConfig.TuistXcodeProjectOptions
public typealias TuistSwiftPackageOptions = TuistConfig.TuistSwiftPackageOptions
public typealias CompatibleXcodeVersions = TuistConfig.CompatibleXcodeVersions
public typealias PluginLocation = TuistConfig.PluginLocation
public typealias CacheProfileType = TuistConfig.CacheProfileType
public typealias BaseCacheProfile = TuistConfig.BaseCacheProfile
public typealias CacheProfile = TuistConfig.CacheProfile
public typealias CacheProfiles = TuistConfig.CacheProfiles
public typealias CacheOptions = TuistConfig.CacheOptions
public typealias TargetQuery = TuistConfig.TargetQuery

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
