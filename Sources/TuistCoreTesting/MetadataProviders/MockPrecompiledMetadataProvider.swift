import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public class MockPrecompiledMetadataProvider: PrecompiledMetadataProviding {
    public init() {}

    public var architecturesStub: ((AbsolutePath) throws -> [BinaryArchitecture])?
    public func architectures(binaryPath: AbsolutePath) throws -> [BinaryArchitecture] {
        if let architecturesStub = architecturesStub {
            return try architecturesStub(binaryPath)
        } else {
            return []
        }
    }

    public var linkingStub: ((AbsolutePath) throws -> BinaryLinking)?
    public func linking(binaryPath: AbsolutePath) throws -> BinaryLinking {
        if let linkingStub = linkingStub {
            return try linkingStub(binaryPath)
        } else {
            return .dynamic
        }
    }

    public var uuidsStub: ((AbsolutePath) throws -> Set<UUID>)?
    public func uuids(binaryPath: AbsolutePath) throws -> Set<UUID> {
        if let uuidsStub = uuidsStub {
            return try uuidsStub(binaryPath)
        } else {
            return Set()
        }
    }
}
