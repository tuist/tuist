import Path

public enum SwiftPackageManagerPaths {
    public static let checkoutsDirectoryName = "checkouts"
    public static let defaultScratchDirectoryName = ".build"

    public static func checkoutsDirectory(in scratchDirectory: AbsolutePath) -> AbsolutePath {
        scratchDirectory.appending(component: checkoutsDirectoryName)
    }

    public static func isPath(_ path: AbsolutePath, inCheckoutsOf scratchDirectory: AbsolutePath) -> Bool {
        path.isDescendantOfOrEqual(to: checkoutsDirectory(in: scratchDirectory))
    }

    public static func isPath(
        _ path: AbsolutePath,
        inSwiftPackageManagerCheckoutsOf scratchDirectory: AbsolutePath?
    ) -> Bool {
        if let scratchDirectory {
            return isPath(path, inCheckoutsOf: scratchDirectory)
        }
        return defaultScratchDirectory(containingCheckout: path) != nil
    }

    public static func scratchDirectory(containingCheckout path: AbsolutePath) -> AbsolutePath? {
        var current = path
        while current != .root {
            if current.basename == checkoutsDirectoryName {
                return current.parentDirectory
            }
            current = current.parentDirectory
        }
        return nil
    }

    public static func defaultScratchDirectory(containingCheckout path: AbsolutePath) -> AbsolutePath? {
        guard let scratchDirectory = scratchDirectory(containingCheckout: path),
              scratchDirectory.basename == defaultScratchDirectoryName
        else { return nil }
        return scratchDirectory
    }

    public static func scratchDirectory(
        containingCheckout path: AbsolutePath,
        knownScratchDirectory: AbsolutePath?
    ) -> AbsolutePath? {
        if let knownScratchDirectory, isPath(path, inCheckoutsOf: knownScratchDirectory) {
            return knownScratchDirectory
        }
        return defaultScratchDirectory(containingCheckout: path)
    }
}
