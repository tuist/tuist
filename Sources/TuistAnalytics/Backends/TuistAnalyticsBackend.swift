import Foundation
import RxSwift

protocol TuistAnalyticsBackend: AnyObject {
    func send(commandEvent: CommandEvent) throws -> Single<Void>
}
