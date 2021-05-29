import Foundation
import RxSwift
import TuistSupport

public protocol LabClienting {
    func request<T, E>(_ resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)>
}
