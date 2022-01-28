import Foundation
import TuistSupport

extension AsyncThrowingStream where Element == SystemEvent<XcodeBuildOutput> {
    public func printFormattedOutput() async throws {
        for try await element in self {
            switch element {
            case let .standardError(error):
                let lines = error.raw.split(separator: "\n")
                for line in lines where !line.isEmpty {
                    logger.error("\(line)")
                }
            case let .standardOutput(output):
                let lines = output.raw.split(separator: "\n")
                for line in lines where !line.isEmpty {
                    logger.notice("\(line)")
                }
            }
        }
    }
}
