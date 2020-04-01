import Foundation
import RxSwift
import TuistSupport

public extension Observable where Element == SystemEvent<XcodeBuildOutput> {
    func printFormattedOutput() -> Observable<SystemEvent<XcodeBuildOutput>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                let string = error.formatted ?? error.raw
                if let data = string.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            case let .standardOutput(output):
                let string = output.formatted ?? output.raw
                if let data = string.data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
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
