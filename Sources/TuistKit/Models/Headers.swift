import Basic
import Foundation
import TuistCore
import xcodeproj

/// Headers
class Headers: Equatable {
    // MARK: - Attributes

    let `public`: [AbsolutePath]
    let `private`: [AbsolutePath]
    let project: [AbsolutePath]

    // MARK: - Init

    init(public: [AbsolutePath],
         private: [AbsolutePath],
         project: [AbsolutePath]) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }

    // MARK: - Equatable

    static func == (lhs: Headers, rhs: Headers) -> Bool {
        return lhs.public == rhs.public &&
            lhs.private == rhs.private &&
            lhs.project == rhs.project
    }
}
