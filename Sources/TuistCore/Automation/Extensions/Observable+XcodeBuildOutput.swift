import Foundation
import RxSwift
import TuistSupport

public extension Observable where Element == SystemEvent<XcodeBuildOutput> {
    func printFormattedOutput() -> Observable<SystemEvent<XcodeBuildOutput>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                logger.error("\(error.raw.dropLast())")
            case let .standardOutput(output):
                logger.notice("\(output.raw.dropLast())")
            }
        })
    }

    func printRawErrors() -> Observable<SystemEvent<XcodeBuildOutput>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                logger.error("\(error.raw)")
            default:
                break
            }
        })
    }
}
