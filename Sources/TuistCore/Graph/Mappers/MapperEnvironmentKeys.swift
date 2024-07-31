import Foundation
import XcodeGraph

// Common MapperEnvironment keys that need to be shared with the closed source repository.

private struct TestsCacheHashesKey: MapperEnvironmentKey {
    static var defaultValue: [Target: String] = [:]
}

private struct InitialGraphKey: MapperEnvironmentKey {
    static var defaultValue: Graph?
}

extension MapperEnvironment {
    /// Hashes of targets that are missing in the remote storage
    public var testsCacheUntestedHashes: [Target: String] {
        get { self[TestsCacheHashesKey.self] }
        set { self[TestsCacheHashesKey.self] = newValue }
    }

    public var initialGraph: Graph? {
        get { self[InitialGraphKey.self] }
        set { self[InitialGraphKey.self] = newValue }
    }
}
