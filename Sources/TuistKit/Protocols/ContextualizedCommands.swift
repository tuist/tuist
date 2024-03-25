import ArgumentParser
import Foundation
import TuistSupport

public protocol ContextualizedAsyncParsableCommand: AsyncParsableCommand {
    func run(context: Context) async throws
}
