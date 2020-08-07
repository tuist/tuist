import Foundation
import TSCBasic
@testable import TuistCore

public extension Cloud {
    static func test(url: URL = URL.test(),
                     projectId: String = "123",
                     options: [Cloud.Option] = []) -> Cloud
    {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
