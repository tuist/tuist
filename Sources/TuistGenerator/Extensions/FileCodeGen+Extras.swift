import Foundation
import TuistGraph

extension FileCodeGen {
    var rawValue: String {
        switch self {
        case .public:
            return "codegen"
        case .private:
            return "private_codegen"
        case .project:
            return "project_codegen"
        case .disabled:
            return "no_codegen"
        }
    }
}
