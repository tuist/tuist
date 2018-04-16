import Foundation
import SwiftCLI
import xcbuddykit

let cli = CLI(name: "xcbuddy", version: App().version, description: "Xcode projects at scale")

cli.commands = [
    UpdateCommand(),
    DumpCommand(),
    // generate-xcodeproj
    // build
    // test
]

cli.goAndExit()
