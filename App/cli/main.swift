import Foundation
import xcbuddykit

var registry = CommandRegistry(usage: "<command> <options>", overview: "Your Xcode buddy")

registry.register(command: UpdateCommand.self)
registry.register(command: DumpCommand.self)

registry.run()
