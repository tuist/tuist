import Foundation
import RxSwift
import TuistSupport

public extension Observable where Element == SystemEvent<XcodeBuildOutput> {
    func printFormattedOutput() -> Observable<SystemEvent<XcodeBuildOutput>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                if let string = error.formatted {
                    logger.error("\(string)")
                }
                logger.debug("\(error.raw)")
            case let .standardOutput(output):
                if let string = output.formatted {
                    logger.notice("\(string)")
                }
                logger.debug("\(output.raw)")
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
