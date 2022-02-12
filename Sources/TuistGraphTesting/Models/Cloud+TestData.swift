import Foundation
import TSCBasic
import TuistSupportTesting
@testable import TuistGraph

extension Cloud {
    public static func test(
        url: URL = URL.test(),
        projectId: String = "123",
        options: [Cloud.Option] = []
    ) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
