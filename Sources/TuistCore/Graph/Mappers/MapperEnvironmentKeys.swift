import Foundation
import Path
import XcodeGraph

// Common MapperEnvironment keys that need to be shared with the closed source repository.

private struct TestsCacheHashesKey: MapperEnvironmentKey {
    static var defaultValue: [Target: String] = [:]
}

private struct InitialGraphKey: MapperEnvironmentKey {
    static var defaultValue: Graph?
}

private struct TargetTestHashesKey: MapperEnvironmentKey {
    static var defaultValue: [AbsolutePath: [String: String]] = [:]
}

extension MapperEnvironment {
    /// Target hashes for the `test` action.
    public var targetTestHashes: [AbsolutePath: [String: String]] {
        get { self[TargetTestHashesKey.self] }
        set { self[TargetTestHashesKey.self] = newValue }
    }

    public var initialGraph: Graph? {
        get { self[InitialGraphKey.self] }
        set { self[InitialGraphKey.self] = newValue }
    }
}
