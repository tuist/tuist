import Foundation
import TSCBasic
@testable import TuistCore

public extension Scale {
    static func test(url: URL = URL.test(),
                     projectId: String = "123",
                     options: [Scale.Option] = []) -> Scale
    {
        Scale(url: url, projectId: projectId, options: options)
    }
}
