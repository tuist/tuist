import Foundation
import TuistSupport

extension AsyncThrowingStream where Element == SystemEvent<XcodeBuildOutput> {
    public func printFormattedOutput() async throws {
        for try await element in self {
            switch element {
            case let .standardError(error):
                logger.error("\(error.raw.dropLast())")
            case let .standardOutput(output):
                logger.notice("\(output.raw.dropLast())")
            }
        }
    }
}
