//===----------------------------------------------------------------------===//
//
// TuistCASPlugin.swift
// Swift implementation of CAS plugin interface for Tuist server
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - C API Implementation

@_cdecl("llcas_get_plugin_version")
public func llcas_get_plugin_version(_ major: UnsafeMutablePointer<UInt32>, _ minor: UnsafeMutablePointer<UInt32>) {
    major.pointee = 0
    minor.pointee = 1
}

@_cdecl("llcas_string_dispose")
public func llcas_string_dispose(_ str: UnsafeMutablePointer<CChar>?) {
    str?.deallocate()
}

@_cdecl("llcas_cancellable_cancel")
public func llcas_cancellable_cancel(_ cancellable: OpaquePointer?) {
    // Stub implementation for cancellation
}

@_cdecl("llcas_cancellable_dispose")
public func llcas_cancellable_dispose(_ cancellable: OpaquePointer?) {
    // Stub implementation for disposal
}

@_cdecl("llcas_cas_get_ondisk_size")
public func llcas_cas_get_ondisk_size(_ cas: OpaquePointer?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int64 {
    return -1 // Not supported
}

@_cdecl("llcas_cas_set_ondisk_size_limit")
public func llcas_cas_set_ondisk_size_limit(_ cas: OpaquePointer?, _ size_limit: Int64, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    return false // No error, but not implemented
}

@_cdecl("llcas_cas_prune_ondisk_data")
public func llcas_cas_prune_ondisk_data(_ cas: OpaquePointer?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    return false // No error, but not implemented
}

@_cdecl("llcas_cas_options_create")
public func llcas_cas_options_create() -> OpaquePointer? {
    let options = TuistCASOptions()
    return OpaquePointer(Unmanaged.passRetained(options).toOpaque())
}

@_cdecl("llcas_cas_options_dispose")
public func llcas_cas_options_dispose(_ options: OpaquePointer?) {
    guard let options = options else { return }
    let _ = Unmanaged<TuistCASOptions>.fromOpaque(UnsafeMutableRawPointer(options)).takeRetainedValue()
}

@_cdecl("llcas_cas_options_set_client_version")
public func llcas_cas_options_set_client_version(_ options: OpaquePointer?, _ major: UInt32, _ minor: UInt32) {
    guard let options = options else { return }
    let casOptions = Unmanaged<TuistCASOptions>.fromOpaque(UnsafeMutableRawPointer(options)).takeUnretainedValue()
    casOptions.clientVersion = (major, minor)
}

@_cdecl("llcas_cas_options_set_ondisk_path")
public func llcas_cas_options_set_ondisk_path(_ options: OpaquePointer?, _ path: UnsafePointer<CChar>?) {
    guard let options = options, let path = path else { return }
    let casOptions = Unmanaged<TuistCASOptions>.fromOpaque(UnsafeMutableRawPointer(options)).takeUnretainedValue()
    casOptions.path = String(cString: path)
}

@_cdecl("llcas_cas_options_set_option")
public func llcas_cas_options_set_option(_ options: OpaquePointer?, _ key: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    guard let options = options, let key = key, let value = value else { return true }
    let casOptions = Unmanaged<TuistCASOptions>.fromOpaque(UnsafeMutableRawPointer(options)).takeUnretainedValue()
    let keyString = String(cString: key)
    let valueString = String(cString: value)
    
    casOptions.options[keyString] = valueString
    return false // No error
}

@_cdecl("llcas_cas_create")
public func llcas_cas_create(_ options: OpaquePointer?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> OpaquePointer? {
    guard let options = options else { return nil }
    let casOptions = Unmanaged<TuistCASOptions>.fromOpaque(UnsafeMutableRawPointer(options)).takeUnretainedValue()
    
    do {
        let cas = try TuistCAS(options: casOptions)
        return OpaquePointer(Unmanaged.passRetained(cas).toOpaque())
    } catch let createError {
        if let error = error {
            let errorString = createError.localizedDescription
            let cString = UnsafeMutablePointer<CChar>.allocate(capacity: errorString.utf8.count + 1)
            errorString.withCString { ptr in
                cString.initialize(from: ptr, count: errorString.utf8.count + 1)
            }
            error.pointee = cString
        }
        return nil
    }
}

@_cdecl("llcas_cas_dispose")
public func llcas_cas_dispose(_ cas: OpaquePointer?) {
    guard let cas = cas else { return }
    let _ = Unmanaged<TuistCAS>.fromOpaque(UnsafeMutableRawPointer(cas)).takeRetainedValue()
}

@_cdecl("llcas_cas_store_object")
public func llcas_cas_store_object(_ cas: OpaquePointer?, _ data: UnsafeRawPointer?, _ dataSize: Int, _ refs: UnsafePointer<UInt64>?, _ refsCount: Int, _ objectId: UnsafeMutablePointer<UInt64>?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    guard let cas = cas, let data = data, let objectId = objectId else { return true }
    let tuistCAS = Unmanaged<TuistCAS>.fromOpaque(UnsafeMutableRawPointer(cas)).takeUnretainedValue()
    
    let objectData = Data(bytes: data, count: dataSize)
    var refIds: [String] = []
    
    if let refs = refs, refsCount > 0 {
        for i in 0..<refsCount {
            let ref = refs[i]
            refIds.append(String(ref))
        }
    }
    
    do {
        let id = try tuistCAS.storeObject(data: objectData, refs: refIds)
        objectId.pointee = UInt64(id.hash.hashValue)
        return false // No error
    } catch let storeError {
        if let error = error {
            let errorString = storeError.localizedDescription
            let cString = UnsafeMutablePointer<CChar>.allocate(capacity: errorString.utf8.count + 1)
            errorString.withCString { ptr in
                cString.initialize(from: ptr, count: errorString.utf8.count + 1)
            }
            error.pointee = cString
        }
        return true // Error
    }
}

@_cdecl("llcas_cas_load_object")
public func llcas_cas_load_object(_ cas: OpaquePointer?, _ objectId: UInt64, _ object: UnsafeMutablePointer<UInt64>?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    guard let cas = cas, let object = object else { return 2 }
    let tuistCAS = Unmanaged<TuistCAS>.fromOpaque(UnsafeMutableRawPointer(cas)).takeUnretainedValue()
    
    do {
        let id = TuistObjectID(hash: String(objectId))
        if let loadedObject = try tuistCAS.loadObject(id: id) {
            let managedObject = Unmanaged.passRetained(loadedObject)
            object.pointee = UInt64(Int(bitPattern: managedObject.toOpaque()))
            return 0 // LLCAS_LOOKUP_RESULT_SUCCESS
        } else {
            return 1 // LLCAS_LOOKUP_RESULT_NOTFOUND
        }
    } catch let loadError {
        if let error = error {
            let errorString = loadError.localizedDescription
            let cString = UnsafeMutablePointer<CChar>.allocate(capacity: errorString.utf8.count + 1)
            errorString.withCString { ptr in
                cString.initialize(from: ptr, count: errorString.utf8.count + 1)
            }
            error.pointee = cString
        }
        return 2 // LLCAS_LOOKUP_RESULT_ERROR
    }
}

@_cdecl("llcas_loaded_object_get_data")
public func llcas_loaded_object_get_data(_ cas: OpaquePointer?, _ object: UInt64, _ dataPtr: UnsafeMutablePointer<UnsafeRawPointer?>?, _ dataSize: UnsafeMutablePointer<Int>?) {
    guard let objPtr = UnsafeMutableRawPointer(bitPattern: UInt(object)),
          let dataPtr = dataPtr, let dataSize = dataSize else { 
        dataPtr?.pointee = nil
        dataSize?.pointee = 0
        return 
    }
    let loadedObject = Unmanaged<TuistLoadedObject>.fromOpaque(objPtr).takeUnretainedValue()
    dataPtr.pointee = loadedObject.data.withUnsafeBytes { $0.baseAddress }
    dataSize.pointee = loadedObject.data.count
}

@_cdecl("llcas_loaded_object_get_refs")
public func llcas_loaded_object_get_refs(_ cas: OpaquePointer?, _ object: UInt64) -> UInt64 {
    guard let objPtr = UnsafeMutableRawPointer(bitPattern: UInt(object)) else {
        return 0
    }
    let loadedObject = Unmanaged<TuistLoadedObject>.fromOpaque(objPtr).takeUnretainedValue()
    let refs = TuistObjectRefs(refs: loadedObject.refs)
    let managedRefs = Unmanaged.passRetained(refs)
    return UInt64(Int(bitPattern: managedRefs.toOpaque()))
}

@_cdecl("llcas_object_refs_get_count")
public func llcas_object_refs_get_count(_ cas: OpaquePointer?, _ refs: UInt64) -> Int {
    guard let refsPtr = UnsafeMutableRawPointer(bitPattern: UInt(refs)) else { return 0 }
    let objectRefs = Unmanaged<TuistObjectRefs>.fromOpaque(refsPtr).takeUnretainedValue()
    return objectRefs.refs.count
}

@_cdecl("llcas_object_refs_get_id")
public func llcas_object_refs_get_id(_ cas: OpaquePointer?, _ refs: UInt64, _ index: Int) -> UInt64 {
    guard let refsPtr = UnsafeMutableRawPointer(bitPattern: UInt(refs)) else {
        return 0
    }
    let objectRefs = Unmanaged<TuistObjectRefs>.fromOpaque(refsPtr).takeUnretainedValue()
    guard index >= 0 && index < objectRefs.refs.count else {
        return 0
    }
    let ref = objectRefs.refs[index]
    return UInt64(ref.hash.hashValue)
}

@_cdecl("llcas_actioncache_put_for_digest_async")
public func llcas_actioncache_put_for_digest_async(_ cas: OpaquePointer?, _ keyData: UnsafePointer<UInt8>?, _ keySize: Int, _ objectId: UInt64, _ globally: Bool, _ context: UnsafeMutableRawPointer?, _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Bool, UnsafeMutablePointer<CChar>?) -> Void, _ cancellable: UnsafeMutablePointer<OpaquePointer?>?) {
    guard let cas = cas, let keyData = keyData else { 
        callback(context, true, nil)
        return 
    }
    let tuistCAS = Unmanaged<TuistCAS>.fromOpaque(UnsafeMutableRawPointer(cas)).takeUnretainedValue()
    
    Task {
        do {
            let keyBytes = Data(bytes: keyData, count: keySize)
            let keyId = TuistObjectID(hash: keyBytes.hexString)
            let valueId = TuistObjectID(hash: String(objectId))
            try await tuistCAS.putActionCache(keyId: keyId, objectId: valueId)
            callback(context, false, nil)
        } catch let putError {
            let errorString = putError.localizedDescription
            let cString = UnsafeMutablePointer<CChar>.allocate(capacity: errorString.utf8.count + 1)
            errorString.withCString { ptr in
                cString.initialize(from: ptr, count: errorString.utf8.count + 1)
            }
            callback(context, true, cString)
        }
    }
}

@_cdecl("llcas_actioncache_get_for_digest_async")
public func llcas_actioncache_get_for_digest_async(_ cas: OpaquePointer?, _ keyData: UnsafePointer<UInt8>?, _ keySize: Int, _ globally: Bool, _ context: UnsafeMutableRawPointer?, _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32, UInt64, UnsafeMutablePointer<CChar>?) -> Void, _ cancellable: UnsafeMutablePointer<OpaquePointer?>?) {
    guard let cas = cas, let keyData = keyData else {
        callback(context, 2, 0, nil)
        return
    }
    let tuistCAS = Unmanaged<TuistCAS>.fromOpaque(UnsafeMutableRawPointer(cas)).takeUnretainedValue()
    
    Task {
        do {
            let keyBytes = Data(bytes: keyData, count: keySize)
            let keyId = TuistObjectID(hash: keyBytes.hexString)
            if let objectId = try await tuistCAS.getActionCache(keyId: keyId) {
                callback(context, 0, UInt64(objectId.hash.hashValue), nil)
            } else {
                callback(context, 1, 0, nil)
            }
        } catch let getError {
            let errorString = getError.localizedDescription
            let cString = UnsafeMutablePointer<CChar>.allocate(capacity: errorString.utf8.count + 1)
            errorString.withCString { ptr in
                cString.initialize(from: ptr, count: errorString.utf8.count + 1)
            }
            callback(context, 2, 0, cString)
        }
    }
}

@_cdecl("llcas_objectid_get_digest")
public func llcas_objectid_get_digest(_ cas: OpaquePointer?, _ objectId: UInt64, _ digestData: UnsafeMutablePointer<UnsafePointer<UInt8>?>?, _ digestSize: UnsafeMutablePointer<Int>?) {
    guard let digestData = digestData, let digestSize = digestSize else { return }
    // Convert object ID to digest (simplified implementation)
    let hashString = String(objectId)
    let data = Data(hashString.utf8)
    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    data.copyBytes(to: ptr, count: data.count)
    digestData.pointee = UnsafePointer(ptr)
    digestSize.pointee = data.count
}

@_cdecl("llcas_cas_get_hash_schema_name")
public func llcas_cas_get_hash_schema_name(_ cas: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
    let schemaName = "SHA256"
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: schemaName.count + 1)
    schemaName.withCString { cString in
        ptr.initialize(from: cString, count: schemaName.count + 1)
    }
    return ptr
}

@_cdecl("llcas_digest_parse")
public func llcas_digest_parse(_ cas: OpaquePointer?, _ printed_digest: UnsafePointer<CChar>?, _ bytes: UnsafeMutablePointer<UInt8>?, _ bytes_size: Int, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UInt32 {
    guard let printed_digest = printed_digest else { return 0 }
    let digestString = String(cString: printed_digest)
    let data = Data(digestString.utf8)
    
    if bytes_size < data.count {
        return UInt32(data.count) // Return required size
    }
    
    if let bytes = bytes {
        data.copyBytes(to: bytes, count: min(data.count, bytes_size))
    }
    
    return UInt32(data.count)
}

@_cdecl("llcas_digest_print")
public func llcas_digest_print(_ cas: OpaquePointer?, _ digestData: UnsafePointer<UInt8>?, _ digestSize: Int, _ printed_id: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    guard let printed_id = printed_id, let digestData = digestData else { return true }
    let data = Data(bytes: digestData, count: digestSize)
    let digestString = data.map { String(format: "%02x", $0) }.joined()
    
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: digestString.count + 1)
    digestString.withCString { cString in
        ptr.initialize(from: cString, count: digestString.count + 1)
    }
    printed_id.pointee = ptr
    
    return false // No error
}

@_cdecl("llcas_cas_get_objectid")
public func llcas_cas_get_objectid(_ cas: OpaquePointer?, _ digestData: UnsafePointer<UInt8>?, _ digestSize: Int, _ p_id: UnsafeMutablePointer<UInt64>?, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    guard let p_id = p_id, let digestData = digestData else { return true }
    let data = Data(bytes: digestData, count: digestSize)
    p_id.pointee = UInt64(data.hashValue)
    return false // No error
}

@_cdecl("llcas_cas_contains_object")
public func llcas_cas_contains_object(_ cas: OpaquePointer?, _ objectId: UInt64, _ globally: Bool, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    return 1 // LLCAS_LOOKUP_RESULT_NOTFOUND for now
}

@_cdecl("llcas_cas_load_object_async")
public func llcas_cas_load_object_async(_ cas: OpaquePointer?, _ objectId: UInt64, _ context: UnsafeMutableRawPointer?, _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, Int32, UInt64, UnsafeMutablePointer<CChar>?) -> Void, _ cancellable: UnsafeMutablePointer<OpaquePointer?>?) {
    Task {
        callback(context, 1, 0, nil) // Not found for now
    }
}

@_cdecl("llcas_actioncache_get_for_digest")
public func llcas_actioncache_get_for_digest(_ cas: OpaquePointer?, _ keyData: UnsafePointer<UInt8>?, _ keySize: Int, _ p_value: UnsafeMutablePointer<UInt64>?, _ globally: Bool, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    return 1 // LLCAS_LOOKUP_RESULT_NOTFOUND for now
}

@_cdecl("llcas_actioncache_put_for_digest")
public func llcas_actioncache_put_for_digest(_ cas: OpaquePointer?, _ keyData: UnsafePointer<UInt8>?, _ keySize: Int, _ value: UInt64, _ globally: Bool, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Bool {
    return false // No error for now
}

// MARK: - Supporting Swift Classes

public class TuistCASOptions {
    var clientVersion: (UInt32, UInt32) = (0, 1)
    var path: String = "/tmp/tuist-cas"
    var options: [String: String] = [:]
}

public struct TuistObjectID {
    let hash: String
}

public class TuistLoadedObject {
    let data: Data
    let refs: [TuistObjectID]
    
    init(data: Data, refs: [TuistObjectID]) {
        self.data = data
        self.refs = refs
    }
}

public class TuistObjectRefs {
    let refs: [TuistObjectID]
    
    init(refs: [TuistObjectID]) {
        self.refs = refs
    }
}

public class TuistCAS {
    private let options: TuistCASOptions
    private let serverURL: String
    
    init(options: TuistCASOptions) throws {
        self.options = options
        self.serverURL = options.options["server_url"] ?? "https://tuist.dev"
    }
    
    func storeObject(data: Data, refs: [String]) throws -> TuistObjectID {
        // Implementation would make HTTP request to Tuist server
        // For now, return a mock hash
        let hash = data.sha256
        return TuistObjectID(hash: hash)
    }
    
    func loadObject(id: TuistObjectID) throws -> TuistLoadedObject? {
        // Implementation would make HTTP request to Tuist server
        // For now, return nil (not found)
        return nil
    }
    
    func putActionCache(keyId: TuistObjectID, objectId: TuistObjectID) async throws {
        // Implementation would make HTTP request to Tuist server
    }
    
    func getActionCache(keyId: TuistObjectID) async throws -> TuistObjectID? {
        // Implementation would make HTTP request to Tuist server
        return nil
    }
}

extension Data {
    var sha256: String {
        // Simple implementation - in real code you'd use CryptoKit
        return "mock_hash_\(self.hashValue)"
    }
    
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
