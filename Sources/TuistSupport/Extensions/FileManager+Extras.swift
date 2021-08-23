import Foundation

extension FileManager {
    func subpathsResolvingSymbolicLinks(atPath path: String) -> [String] {
        subpathsResolvingSymbolicLinks(atNestedPath: nil, basePath: path)
    }

    private func subpathsResolvingSymbolicLinks(atNestedPath nestedPath: String?, basePath: String) -> [String] {
        let currentLevelPath = nestedPath.map { "\(basePath)/\($0)" } ?? basePath

        guard let currentLevelSubpaths = subpaths(atPath: currentLevelPath) else {
            return []
        }

        var resolvedSubpaths: [String] = []
        for subpath in currentLevelSubpaths {
            let relativeSubpath = nestedPath.map { "\($0)/\(subpath)" } ?? subpath
            let completeSubpath = "\(basePath)/\(relativeSubpath)"
            if isDirectory(path: completeSubpath), isSymbolicLink(path: completeSubpath) {
                resolvedSubpaths.append(
                    contentsOf: subpathsResolvingSymbolicLinks(atNestedPath: relativeSubpath, basePath: basePath)
                )
            }
            resolvedSubpaths.append(relativeSubpath)
        }

        return resolvedSubpaths
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
