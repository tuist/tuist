import Basic
import Darwin
import Foundation

let systemGlob = Darwin.glob

extension AbsolutePath {
    static var current: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    public func glob(_ pattern: String) -> [AbsolutePath] {
        var gt = glob_t()
        let cPattern = strdup(appending(RelativePath(pattern)).asString)
        defer {
            globfree(&gt)
            free(cPattern)
        }

        let flags = GLOB_TILDE | GLOB_BRACE | GLOB_MARK
        if systemGlob(cPattern, flags, nil, &gt) == 0 {
            let matchc = gt.gl_matchc
            return (0 ..< Int(matchc)).compactMap { index in
                if let path = String(validatingUTF8: gt.gl_pathv[index]!) {
                    return AbsolutePath(path)
                }
                return nil
            }
        }

        // GLOB_NOMATCH
        return []
    }
}
