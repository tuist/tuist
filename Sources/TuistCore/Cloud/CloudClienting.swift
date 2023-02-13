import Foundation
import TuistSupport

public protocol CloudClienting {
    func request<T, E>(_ resource: HTTPResource<T, E>) async throws -> (object: T, response: HTTPURLResponse)
}
