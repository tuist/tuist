import Basic
import Darwin
import Foundation

let systemGlob = Darwin.glob

extension AbsolutePath {
    static var current: AbsolutePath {
        return AbsolutePath(FileManager.default.currentDirectoryPath)
    }

    public func glob(_ pattern: String) -> [AbsolutePath] {
        var globt = glob_t()
        let cPattern = strdup(appending(RelativePath(pattern)).asString)
        defer {
            globfree(&globt)
            free(cPattern)
        }

        let flags = GLOB_TILDE | GLOB_BRACE | GLOB_MARK
        if systemGlob(cPattern, flags, nil, &globt) == 0 {
            let matchc = globt.gl_matchc
            return (0 ..< Int(matchc)).compactMap { index in
                if let path = String(validatingUTF8: globt.gl_pathv[index]!) {
                    return AbsolutePath(path)
                }
                return nil
            }
        }
        return []
    }
}
