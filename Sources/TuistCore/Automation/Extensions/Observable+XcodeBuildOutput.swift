import Foundation
import RxSwift
import TuistSupport

extension Observable where Element == SystemEvent<XcodeBuildOutput> {
    public func printFormattedOutput() -> Observable<SystemEvent<XcodeBuildOutput>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                logger.error("\(error.raw.dropLast())")
            case let .standardOutput(output):
                logger.notice("\(output.raw.dropLast())")
            }
        })
    }

    public func printRawErrors() -> Observable<SystemEvent<XcodeBuildOutput>> {
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
