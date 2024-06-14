import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.FileCodeGen {
    static func from(manifest: ProjectDescription.FileCodeGen) -> XcodeGraph.FileCodeGen {
        switch manifest {
        case .public:
            return .public
        case .private:
            return .private
        case .project:
            return .project
        case .disabled:
            return .disabled
        }
    }
}
