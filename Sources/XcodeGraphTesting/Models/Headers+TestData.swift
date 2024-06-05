import Foundation
import TSCBasic
@testable import XcodeGraph

extension Headers {
    public static func test(
        public: [AbsolutePath] = [],
        private: [AbsolutePath] = [],
        project: [AbsolutePath] = []
    ) -> Headers {
        Headers(
            public: `public`,
            private: `private`,
            project: project
        )
    }
}
