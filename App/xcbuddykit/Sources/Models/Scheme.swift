import Foundation
import Unbox

class Scheme: Unboxable {
    let name: String
    let shared: Bool
    let buildAction: BuildAction?
    let testAction: TestAction?
    let runAction: RunAction?

    required init(unboxer: Unboxer) throws {
        name = try unboxer.unbox(key: "name")
        shared = try unboxer.unbox(key: "shared")
        buildAction = unboxer.unbox(key: "build_action")
        testAction = unboxer.unbox(key: "test_action")
        runAction = unboxer.unbox(key: "run_action")
    }
}

public class Arguments: Unboxable {
    let environment: [String: String]
    let launch: [String: Bool]

    public required init(unboxer: Unboxer) throws {
        environment = try unboxer.unbox(key: "environment")
        launch = try unboxer.unbox(key: "launch")
    }
}

public class BuildAction: Unboxable {
    let targets: [String]

    public required init(unboxer: Unboxer) throws {
        targets = try unboxer.unbox(key: "targets")
    }
}

public class TestAction: Unboxable {
    let targets: [String]
    let arguments: Arguments?
    let config: BuildConfiguration
    let coverage: Bool

    public required init(unboxer: Unboxer) throws {
        targets = try unboxer.unbox(key: "targets")
        arguments = unboxer.unbox(key: "arguments")
        config = try unboxer.unbox(key: "config")
        coverage = try unboxer.unbox(key: "coverage")
    }
}

class RunAction: Unboxable {
    let config: BuildConfiguration
    let executable: String?
    let arguments: Arguments?

    required init(unboxer: Unboxer) throws {
        config = try unboxer.unbox(key: "config")
        executable = unboxer.unbox(key: "executable")
        arguments = unboxer.unbox(key: "arguments")
    }
}
