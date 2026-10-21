import Foundation

/// `realpath` of a path, remembered per path since the files of a build share a few directories. A
/// path that no longer exists resolves through its longest existing ancestor with the rest appended,
/// so a file the build names but the checkout lost still canonicalizes.
final class PathCanonicalizer {
    private var resolved: [String: String] = [:]

    /// The whole path resolved, the path itself included when it is a symbolic link.
    func canonical(_ path: String) -> String {
        if let known = resolved[path] { return known }
        let canonical: String
        if let pointer = realpath(path, nil) {
            canonical = String(cString: pointer)
            free(pointer)
        } else {
            let parent = (path as NSString).deletingLastPathComponent
            canonical = parent.isEmpty || parent == "/" || parent == path
                ? path
                : self.canonical(parent) + "/" + (path as NSString).lastPathComponent
        }
        resolved[path] = canonical
        return canonical
    }

    /// The file's directory resolved and its own name kept, so files sharing a directory resolve it once.
    func canonicalFile(_ path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != "/" else { return path }
        return canonical(directory) + "/" + (path as NSString).lastPathComponent
    }
}
