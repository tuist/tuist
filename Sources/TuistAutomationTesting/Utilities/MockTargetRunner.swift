import TSCBasic
import struct TSCUtility.Version
import TuistAutomation
import TuistGraph

public final class MockTargetRunner: TargetRunning {
    public init() {}

    public var runTargetStub: (
        (GraphTarget, AbsolutePath, String, String?, Version?, Version?, String?, [String]) throws
            -> Void
    )?
    public func runTarget(
        _ target: GraphTarget,
        workspacePath: AbsolutePath,
        schemeName: String,
        configuration: String?,
        minVersion: Version?,
        version: Version?,
        deviceName: String?,
        arguments: [String]
    ) throws {
        try runTargetStub?(target, workspacePath, schemeName, configuration, minVersion, version, deviceName, arguments)
    }

    public var assertCanRunTargetStub: ((Target) throws -> Void)?
    public func assertCanRunTarget(_ target: Target) throws {
        try assertCanRunTargetStub?(target)
    }
}
