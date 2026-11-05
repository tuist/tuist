import ArgumentParser
import Foundation

struct SandboxOptions: ParsableArguments {
    struct Values {
        let account: String?
        let path: String?
        let json: Bool
    }

    @Option(name: .long, help: "Account handle. Defaults to the account in the project's full handle.")
    var account: String?
    @Option(name: .shortAndLong, help: "Project directory.", completion: .directory)
    var path: String?
    @Flag(help: "Return the response as JSON. Unknown optional values are omitted.")
    var json = false

    var values: Values { Values(account: account, path: path, json: json) }
}

/// The sandbox a command acts on.
struct SandboxID: ParsableArguments {
    @Argument(help: "Sandbox UUID.")
    var sandboxID: String

    func validate() throws {
        guard UUID(uuidString: sandboxID) != nil else { throw ValidationError("Sandbox ID must be a UUID.") }
    }
}
