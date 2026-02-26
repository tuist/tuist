import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping a PBXHeadersBuildPhase into a Headers model.
protocol PBXHeadersBuildPhaseMapping {
    /// Converts the given headers build phase into a `Headers` object.
    /// - Parameters:
    ///   - headersBuildPhase: The build phase containing header files.
    ///   - xcodeProj: The `XcodeProj` used for resolving file paths.
    /// - Returns: A `Headers` object, or `nil` if there are no valid header files.
    /// - Throws: If any file paths cannot be resolved.
    func map(_ headersBuildPhase: PBXHeadersBuildPhase, xcodeProj: XcodeProj) throws -> Headers?
}

/// Maps a `PBXHeadersBuildPhase` to a `Headers` domain model.
struct PBXHeadersBuildPhaseMapper: PBXHeadersBuildPhaseMapping {
    func map(_ headersBuildPhase: PBXHeadersBuildPhase, xcodeProj: XcodeProj) throws -> Headers? {
        // Gather all valid HeaderInfo objects
        let headerInfos = try (headersBuildPhase.files ?? []).compactMap {
            try mapHeaderFile($0, xcodeProj: xcodeProj)
        }

        guard !headerInfos.isEmpty else {
            return nil
        }

        let publicHeaders = headerInfos
            .filter { $0.visibility == .public }
            .map(\.path)
        let privateHeaders = headerInfos
            .filter { $0.visibility == .private }
            .map(\.path)
        let projectHeaders = headerInfos
            .filter { $0.visibility == .project }
            .map(\.path)

        return Headers(
            public: publicHeaders,
            private: privateHeaders,
            project: projectHeaders
        )
    }

    // MARK: - Private Helpers

    /// Converts a single `PBXBuildFile` into a `HeaderInfo` if it's a valid header reference.
    private func mapHeaderFile(_ buildFile: PBXBuildFile, xcodeProj: XcodeProj) throws -> HeaderInfo? {
        guard let pbxElement = buildFile.file,
              let pathString = try pbxElement.fullPath(sourceRoot: xcodeProj.srcPathString)
        else {
            return nil
        }

        let absolutePath = try AbsolutePath(validating: pathString)
        let attributes = buildFile.attributes

        let visibility: HeaderInfo.HeaderVisibility
        if attributes?.contains(HeaderAttribute.public.rawValue) == true {
            visibility = .public
        } else if attributes?.contains(HeaderAttribute.private.rawValue) == true {
            visibility = .private
        } else {
            visibility = .project
        }

        return HeaderInfo(path: absolutePath, visibility: visibility)
    }
}

/// Internal struct used to capture a single header file’s path and visibility.
private struct HeaderInfo {
    let path: AbsolutePath
    let visibility: HeaderVisibility

    enum HeaderVisibility {
        case `public`
        case `private`
        case project
    }
}
