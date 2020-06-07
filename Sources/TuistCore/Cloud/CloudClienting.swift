import Foundation
import RxSwift
import TuistSupport

public protocol CloudClienting {
    func request<T>(_ resource: HTTPResource<T, CloudResponseError>) -> Single<(object: T, response: HTTPURLResponse)>
}
