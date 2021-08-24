import Foundation

extension FileManager {
    func subdirectoriesResolvingSymbolicLinks(atPath path: String) -> [String] {
        subdirectoriesResolvingSymbolicLinks(atNestedPath: nil, basePath: path)
    }

    private func subdirectoriesResolvingSymbolicLinks(atNestedPath nestedPath: String?, basePath: String) -> [String] {
        let currentLevelPath = nestedPath.map { NSString(string: basePath).appendingPathComponent($0) } ?? basePath
        let resolvedCurrentLevelPath = resolvingSymbolicLinks(path: currentLevelPath)
        guard
            let resolvedSubpathsFromCurrentRoot = try? subpathsOfDirectory(atPath: resolvedCurrentLevelPath)
        else {
            return []
        }

        var resolvedSubpaths: [String] = []
        for subpath in resolvedSubpathsFromCurrentRoot {
            let relativeSubpath = nestedPath.map { NSString(string: $0).appendingPathComponent(subpath) } ?? subpath
            let completeSubpath = NSString(string: basePath).appendingPathComponent(relativeSubpath)

            if isSymbolicLinkToDirectory(path: completeSubpath) {
                resolvedSubpaths.append(relativeSubpath)
                resolvedSubpaths.append(
                    contentsOf: subdirectoriesResolvingSymbolicLinks(atNestedPath: relativeSubpath, basePath: basePath)
                )
            } else if isDirectory(path: completeSubpath) {
                resolvedSubpaths.append(relativeSubpath)
            }
        }

        return resolvedSubpaths
    }

    private func isSymbolicLinkToDirectory(path: String) -> Bool {
        let pathResolvingSymbolicLinks = resolvingSymbolicLinks(path: path)
        return pathResolvingSymbolicLinks != path && isDirectory(path: pathResolvingSymbolicLinks)
    }

    private func resolvingSymbolicLinks(path: String) -> String {
        guard let destination = try? destinationOfSymbolicLink(atPath: path) else {
            return path
        }

        return resolvingSymbolicLinks(path: destination)
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
