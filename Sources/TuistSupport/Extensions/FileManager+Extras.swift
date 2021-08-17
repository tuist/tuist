import Foundation

extension FileManager {
    func subpathsResolvingSymbolicLinks(atPath path: String) -> [String] {
        subpathsResolvingSymbolicLinks(atPath: path, basePath: nil)
    }

    private func subpathsResolvingSymbolicLinks(atPath path: String, basePath: String?) -> [String] {
        let currentPath = basePath.map { "\($0)/\(path)" } ?? path

        guard let shallowSubpaths = subpaths(atPath: currentPath) else {
            return []
        }

        var resolvedSubpaths: [String] = []
        for subpath in shallowSubpaths {
            let completeSubpath = "\(currentPath)/\(subpath)"
            if isDirectory(path: completeSubpath), isSymbolicLink(path: completeSubpath) {
                resolvedSubpaths.append(contentsOf: subpathsResolvingSymbolicLinks(atPath: subpath, basePath: currentPath))
            }
            resolvedSubpaths.append(completeSubpath)
        }

        return resolvedSubpaths.sorted()
    }

    private func isSymbolicLink(path: String) -> Bool {
        return (try? destinationOfSymbolicLink(atPath: path)) != nil
    }

    func isDirectory(path: String) -> Bool {
        #if os(macOS)
            var isDirectoryBool = ObjCBool(false)
        #else
            var isDirectoryBool = false
        #endif
        var isDirectory = fileExists(atPath: path, isDirectory: &isDirectoryBool)
        #if os(macOS)
            isDirectory = isDirectory && isDirectoryBool.boolValue
        #else
            isDirectory = isDirectory && isDirectoryBool
        #endif

        return isDirectory
    }
}
