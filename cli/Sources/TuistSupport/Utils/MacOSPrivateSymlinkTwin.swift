/// The other spelling of a path under `/tmp`, `/var` or `/etc`, which on macOS are symbolic links into
/// `/private`: `/tmp/x` for `/private/tmp/x` and the other way around. Any other path, including one
/// elsewhere under `/private`, has no twin.
public func macOSPrivateSymlinkTwin(of path: String) -> String? {
    for directory in ["/tmp", "/var", "/etc"] {
        let privateDirectory = "/private" + directory
        if path == privateDirectory || path.hasPrefix(privateDirectory + "/") {
            return String(path.dropFirst("/private".count))
        }
        if path == directory || path.hasPrefix(directory + "/") {
            return "/private" + path
        }
    }
    return nil
}
