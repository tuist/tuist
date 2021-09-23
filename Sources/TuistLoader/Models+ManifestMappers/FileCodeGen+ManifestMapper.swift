import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.FileCodeGen {
    static func from(manifest: ProjectDescription.FileCodeGen) -> TuistGraph.FileCodeGen {
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
