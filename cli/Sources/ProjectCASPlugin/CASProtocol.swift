import Foundation
import SWBUtil

public protocol CASProtocol: Sendable {
    associatedtype Object: CASObjectProtocol
    typealias DataID = Object.DataID

    func store(object: Object) async throws -> DataID
    func load(id: DataID) async throws -> Object?
    func contains(id: DataID) async throws -> Bool
    func delete(id: DataID) async throws
}

public protocol CASObjectProtocol: Equatable, Sendable {
    associatedtype DataID: Equatable, Sendable

    var data: ByteString { get }
    var refs: [DataID] { get }

    init(data: ByteString, refs: [DataID])
}

public protocol ActionCacheProtocol: Sendable {
    associatedtype DataID: Equatable, Sendable

    func cache(objectID: DataID, forKeyID key: DataID) async throws
    func lookupCachedObject(for keyID: DataID) async throws -> DataID?
}