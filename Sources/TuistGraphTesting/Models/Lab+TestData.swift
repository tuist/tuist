import Foundation
import TSCBasic
import TuistSupportTesting
@testable import TuistGraph

public extension Lab {
    static func test(url: URL = URL.test(),
                     projectId: String = "123",
                     options: [Lab.Option] = []) -> Lab
    {
        Lab(url: url, projectId: projectId, options: options)
    }
}
