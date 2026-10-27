import Path

public enum SwiftPackageManagerPaths {
    public static let checkoutsDirectoryName = "checkouts"
    public static let registryDirectoryName = "registry"
    public static let registryDownloadsDirectoryName = "downloads"
    public static let defaultScratchDirectoryName = ".build"

    public static func checkoutsDirectory(in scratchDirectory: AbsolutePath) -> AbsolutePath {
        scratchDirectory.appending(component: checkoutsDirectoryName)
    }

    public static func registryDownloadsDirectory(in scratchDirectory: AbsolutePath) -> AbsolutePath {
        scratchDirectory.appending(components: registryDirectoryName, registryDownloadsDirectoryName)
    }

    /// Whether `path` is one of the package sources SwiftPM materialises inside `scratchDirectory`:
    /// a source-control checkout under `checkouts/`, or a registry download under `registry/downloads/`.
    public static func isPath(_ path: AbsolutePath, inPackageSourcesOf scratchDirectory: AbsolutePath) -> Bool {
        path.isDescendantOfOrEqual(to: checkoutsDirectory(in: scratchDirectory))
            || path.isDescendantOfOrEqual(to: registryDownloadsDirectory(in: scratchDirectory))
    }

    public static func isPath(
        _ path: AbsolutePath,
        inSwiftPackageManagerPackageSourcesOf scratchDirectory: AbsolutePath?
    ) -> Bool {
        if let scratchDirectory {
            return isPath(path, inPackageSourcesOf: scratchDirectory)
        }
        return defaultScratchDirectory(containingPackageSource: path) != nil
    }

    public static func scratchDirectory(containingPackageSource path: AbsolutePath) -> AbsolutePath? {
        var current = path
        while current != .root {
            if current.basename == checkoutsDirectoryName {
                return current.parentDirectory
            }
            if current.basename == registryDownloadsDirectoryName,
               current.parentDirectory.basename == registryDirectoryName
            {
                return current.parentDirectory.parentDirectory
            }
            current = current.parentDirectory
        }
        return nil
    }

    public static func defaultScratchDirectory(containingPackageSource path: AbsolutePath) -> AbsolutePath? {
        guard let scratchDirectory = scratchDirectory(containingPackageSource: path),
              scratchDirectory.basename == defaultScratchDirectoryName
        else { return nil }
        return scratchDirectory
    }

    public static func scratchDirectory(
        containingPackageSource path: AbsolutePath,
        knownScratchDirectory: AbsolutePath?
    ) -> AbsolutePath? {
        if let knownScratchDirectory, isPath(path, inPackageSourcesOf: knownScratchDirectory) {
            return knownScratchDirectory
        }
        return defaultScratchDirectory(containingPackageSource: path)
    }
}
