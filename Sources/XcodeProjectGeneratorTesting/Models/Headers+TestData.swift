import Foundation
import TSCBasic
@testable import XcodeProjectGenerator

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
