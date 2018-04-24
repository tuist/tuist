import Foundation
import xcbuddykit

<<<<<<< HEAD
var registry = CommandRegistry()
=======
let errorHandler = ErrorHandler()
var registry = CommandRegistry(usage: "<command> <options>", overview: "Your Xcode buddy", errorHandler: CommandLineErrorHandler(errorHandler: errorHandler))
registry.register(command: InitCommand.self)
registry.register(command: UpdateCommand.self)
registry.register(command: DumpCommand.self)
>>>>>>> [error-handler] Replace Sentry with Bugsnag
registry.run()
