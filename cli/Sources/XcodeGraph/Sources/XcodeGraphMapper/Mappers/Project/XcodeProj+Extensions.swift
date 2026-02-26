import Foundation
import XcodeProj

/// Errors that may occur while accessing main `PBXProject` information.
enum XcodeProjError: LocalizedError, Equatable {
    case noProjectsFound

    var errorDescription: String? {
        switch self {
        case .noProjectsFound:
            return "No `PBXProject` was found in the `.xcodeproj`"
        }
    }
}

extension XcodeProj {
    func mainPBXProject() throws -> PBXProject {
        guard let pbxProject = pbxproj.projects.first else {
            throw XcodeProjError.noProjectsFound
        }
        return pbxProject
    }
}
