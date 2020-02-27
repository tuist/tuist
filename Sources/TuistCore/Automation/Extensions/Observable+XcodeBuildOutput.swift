import Foundation
import RxSwift
import TuistSupport

public extension Observable where Element == SystemEvent<XcodeBuildOutput> {
    func printFormattedOutput() -> Observable<SystemEvent<XcodeBuildOutput>> {
        self.do(onNext: { event in
            switch event {
            case let .standardError(error):
                Printer.shared.print(errorMessage: "\(error.formatted ?? error.raw)")
            case let .standardOutput(output):
                Printer.shared.print("\(output.formatted ?? output.raw)")
            }
        })
    }
}
