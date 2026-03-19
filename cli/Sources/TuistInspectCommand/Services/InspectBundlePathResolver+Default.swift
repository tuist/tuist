#if !os(macOS)
    import FileSystem
    import Path
    import TuistEnvironment
    import XcodeGraph

    struct DefaultInspectBundlePathResolver: InspectBundlePathResolving {
        private let fileSystem: FileSysteming

        init(fileSystem: FileSysteming = FileSystem()) {
            self.fileSystem = fileSystem
        }

        func resolve(
            bundle: String,
            path _: AbsolutePath,
            configuration _: String?,
            platforms _: [Platform],
            derivedDataPath _: String?
        ) async throws -> AbsolutePath {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let explicitPath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

            if try await fileSystem.exists(explicitPath) || looksLikeBundlePath(explicitPath) {
                return explicitPath
            } else {
                throw InspectBundleCommandServiceError.appleAppNameResolutionNotSupported
            }
        }

        private func looksLikeBundlePath(_ path: AbsolutePath) -> Bool {
            let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
            guard let fileExtension = path.extension else { return false }
            return bundleExtensions.contains(fileExtension)
        }
    }

    func makeInspectBundlePathResolver() -> any InspectBundlePathResolving {
        DefaultInspectBundlePathResolver()
    }
#endif
