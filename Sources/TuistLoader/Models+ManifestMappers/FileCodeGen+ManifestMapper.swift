import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.FileCodeGen {
    static func from(manifest: ProjectDescription.FileCodeGen) -> XcodeProjectGenerator.FileCodeGen {
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
