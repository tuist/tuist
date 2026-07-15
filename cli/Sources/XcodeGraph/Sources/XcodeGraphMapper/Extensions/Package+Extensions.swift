import XcodeGraph

extension Package {
    /// Returns a URL or identifier for the package based on whether it's remote or local.
    var url: String {
        switch kind {
        case let .remote(url, _):
            return url
        case let .local(path):
            return path.pathString
        }
    }
}
