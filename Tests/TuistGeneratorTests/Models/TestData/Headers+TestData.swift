import Basic
import Foundation
@testable import TuistGenerator

extension Headers {
    static func test(public: [AbsolutePath] = [],
                     private: [AbsolutePath] = [],
                     project: [AbsolutePath] = []) -> Headers {
        return Headers(public: `public`,
                       private: `private`,
                       project: project)
    }
}
