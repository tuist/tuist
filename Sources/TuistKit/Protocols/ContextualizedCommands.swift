import Foundation
import ArgumentParser
import TuistSupport

protocol ContextualizedAsyncParsableCommand: AsyncParsableCommand {
    func run(context: Context) async throws
}
