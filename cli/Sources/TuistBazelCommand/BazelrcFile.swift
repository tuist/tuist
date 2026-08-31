import Foundation
import Path
import TuistREAPI

/// The `.bazelrc.tuist` that `tuist bazel setup` generates, and the one thing
/// about it that goes stale.
///
/// The file is per-machine and gitignored, and Bazel reads it once at startup
/// and never again. The endpoint it names belongs to an account whose cache can
/// be placed in another region: the region being left serves for a drain window
/// and is then torn down, taking its hostname out of DNS with it. Nothing in a
/// Bazel build re-resolves, so keeping the file current is the only way the
/// move reaches Bazel — which is why the credential helper, the one piece of
/// Tuist a build actually runs, rewrites it.
enum BazelrcFile {
    static let name = ".bazelrc.tuist"

    private static let remoteCacheFlag = "build --remote_cache="
    private static let credentialHelperFlag = "build --credential_helper="

    static func render(
        endpoint: GRPCEndpoint,
        accountHandle: String,
        projectHandle: String,
        credentialHelperPath: AbsolutePath
    ) -> String {
        """
        \(remoteCacheFlag)\(endpoint.url)
        build --remote_header=x-tuist-account-handle=\(accountHandle)
        \(credentialHelperFlag)\(endpoint.host)=\(credentialHelperPath.pathString)
        build --remote_instance_name=\(projectHandle)

        """
    }

    /// The endpoint URL the file names, or `nil` when it names none.
    static func remoteCache(in contents: String) -> String? {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(remoteCacheFlag) }
            .map { String($0.dropFirst(remoteCacheFlag.count)) }
    }

    /// `contents` pointed at `endpoint`, or `nil` when it already is.
    ///
    /// The two lines naming the host are rewritten and everything else is left
    /// alone, so anything a developer added to the file survives a move. The
    /// credential helper's own path is carried across rather than recomputed:
    /// the file records where Bazel was told to find it, and that is not this
    /// code's to change.
    static func replacingRemoteCache(in contents: String, with endpoint: GRPCEndpoint) -> String? {
        guard let current = remoteCache(in: contents), current != endpoint.url else { return nil }

        let rewritten = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.hasPrefix(remoteCacheFlag) {
                    return "\(remoteCacheFlag)\(endpoint.url)"
                }
                if line.hasPrefix(credentialHelperFlag) {
                    // `<host>=<path>`: the path may itself contain `=`, so split once.
                    let value = line.dropFirst(credentialHelperFlag.count)
                    guard let separator = value.firstIndex(of: "=") else { return String(line) }
                    let path = value[value.index(after: separator)...]
                    return "\(credentialHelperFlag)\(endpoint.host)=\(path)"
                }
                return String(line)
            }
            .joined(separator: "\n")

        return rewritten
    }
}
