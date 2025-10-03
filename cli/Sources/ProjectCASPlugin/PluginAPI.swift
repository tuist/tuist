//===----------------------------------------------------------------------===//
//
// This source file is part of the ProjectCASPlugin project
//
// Copyright (c) 2025 Tuist GmbH
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

@preconcurrency import Foundation
@preconcurrency import SWBUtil
import ProjectCASPluginAPI

// MARK: - Global Remote CAS instance

private actor RemoteCASProvider {
    static let shared = RemoteCASProvider()
    private init() {}

    private var cas: RemoteCAS?

    func set(_ cas: RemoteCAS) {
        self.cas = cas
    }

    func get() -> RemoteCAS? {
        return cas
    }
}

// MARK: - Object Storage

private actor ObjectStore {
    private var loadedObjects: [UInt64: CASObject] = [:]
    private var objectRefs: [UInt64: [DataID]] = [:]
    private var nextID: UInt64 = 1

    func store(object: CASObject) -> UInt64 {
        let id = nextID
        nextID += 1
        loadedObjects[id] = object
        objectRefs[id] = object.refs
        return id
    }

    func getObject(_ id: UInt64) -> CASObject? {
        return loadedObjects[id]
    }

    func getRefs(_ id: UInt64) -> [DataID]? {
        return objectRefs[id]
    }

    func remove(_ id: UInt64) {
        loadedObjects.removeValue(forKey: id)
        objectRefs.removeValue(forKey: id)
    }
}

private let objectStore = ObjectStore()

// MARK: - Helpers

private func withRemoteCAS<T>(
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ body: @escaping (RemoteCAS) async throws -> T
) async -> T? {
    guard let cas = await RemoteCASProvider.shared.get() else {
        if let errorPtr = error {
            errorPtr.pointee = strdup("Remote CAS is not initialized")
        }
        return nil
    }
    do {
        return try await body(cas)
    } catch let err {
        if let errorPtr = error {
            errorPtr.pointee = strdup(String(describing: err))
        }
        return nil
    }
}

private func allocateCString(_ string: String) -> UnsafeMutablePointer<CChar> {
    return strdup(string)
}

// MARK: - C API Implementation

@_cdecl("llcas_get_plugin_version")
public func llcas_get_plugin_version(
    _ major: UnsafeMutablePointer<UInt32>?,
    _ minor: UnsafeMutablePointer<UInt32>?
) {
    major?.pointee = 0
    minor?.pointee = 1
}

@_cdecl("llcas_string_dispose")
public func llcas_string_dispose(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}

@_cdecl("llcas_cancellable_cancel")
public func llcas_cancellable_cancel(_ cancellable: UnsafeMutableRawPointer?) {
    // Not implemented for remote CAS
}

@_cdecl("llcas_cancellable_dispose")
public func llcas_cancellable_dispose(_ cancellable: UnsafeMutableRawPointer?) {
    // Not implemented for remote CAS
}

@_cdecl("llcas_cas_options_create")
public func llcas_cas_options_create() -> UnsafeMutableRawPointer? {
    return UnsafeMutableRawPointer(Unmanaged.passRetained(NSMutableDictionary()).toOpaque())
}

@_cdecl("llcas_cas_options_dispose")
public func llcas_cas_options_dispose(_ options: UnsafeMutableRawPointer?) {
    guard let options else { return }
    Unmanaged<NSMutableDictionary>.fromOpaque(options).release()
}

@_cdecl("llcas_cas_options_set_client_version")
public func llcas_cas_options_set_client_version(
    _ options: UnsafeMutableRawPointer?,
    _ major: UInt32,
    _ minor: UInt32
) {
    // Store version for compatibility checking if needed
}

@_cdecl("llcas_cas_options_set_ondisk_path")
public func llcas_cas_options_set_ondisk_path(
    _ options: UnsafeMutableRawPointer?,
    _ path: UnsafePointer<CChar>?
) {
    // No-op for remote CAS
}

@_cdecl("llcas_cas_options_set_option")
public func llcas_cas_options_set_option(
    _ options: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?,
    _ value: UnsafePointer<CChar>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    guard let options else { return true }
    let dict = Unmanaged<NSMutableDictionary>.fromOpaque(options).takeUnretainedValue()
    if let name, let value {
        dict[String(cString: name)] = String(cString: value)
    }
    return false
}

@_cdecl("llcas_cas_create")
public func llcas_cas_create(
    _ options: UnsafeMutableRawPointer?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutableRawPointer? {
    guard let options else {
        error?.pointee = strdup("Options are required")
        return nil
    }

    let dict = Unmanaged<NSMutableDictionary>.fromOpaque(options).takeUnretainedValue()
    guard let urlString = dict["COMPILATION_CACHE_REMOTE_SERVICE_PATH"] as? String,
          let url = URL(string: urlString) else {
        error?.pointee = strdup("COMPILATION_CACHE_REMOTE_SERVICE_PATH option must be a valid URL")
        return nil
    }

    let cas = ProjectCASPlugin.makeRemoteCAS(baseURL: url)
    Task {
        await RemoteCASProvider.shared.set(cas)
    }

    // Return a dummy handle - we use the singleton
    return UnsafeMutableRawPointer(bitPattern: 1)
}

@_cdecl("llcas_cas_dispose")
public func llcas_cas_dispose(_ cas: UnsafeMutableRawPointer?) {
    // No-op, we manage the singleton internally
}

@_cdecl("llcas_cas_get_ondisk_size")
public func llcas_cas_get_ondisk_size(
    _ cas: UnsafeMutableRawPointer?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int64 {
    // Not supported for remote CAS
    return -1
}

@_cdecl("llcas_cas_set_ondisk_size_limit")
public func llcas_cas_set_ondisk_size_limit(
    _ cas: UnsafeMutableRawPointer?,
    _ size_limit: Int64,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    // Not supported for remote CAS
    error?.pointee = strdup("Operation not supported for remote CAS")
    return true
}

@_cdecl("llcas_cas_prune_ondisk_data")
public func llcas_cas_prune_ondisk_data(
    _ cas: UnsafeMutableRawPointer?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    // Not supported for remote CAS
    error?.pointee = strdup("Operation not supported for remote CAS")
    return true
}

@_cdecl("llcas_cas_get_hash_schema_name")
public func llcas_cas_get_hash_schema_name(_ cas: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    return strdup("SHA256")
}

@_cdecl("llcas_digest_parse")
public func llcas_digest_parse(
    _ cas: UnsafeMutableRawPointer?,
    _ printed_digest: UnsafePointer<CChar>?,
    _ bytes: UnsafeMutablePointer<UInt8>?,
    _ bytes_size: Int,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UInt32 {
    guard let printed_digest else {
        error?.pointee = strdup("Invalid digest string")
        return 0
    }

    let digestString = String(cString: printed_digest)
    guard let data = Data(hexString: digestString) else {
        error?.pointee = strdup("Failed to parse hex digest")
        return 0
    }

    if bytes_size < data.count {
        return UInt32(data.count)
    }

    data.withUnsafeBytes { buffer in
        bytes?.initialize(from: buffer.bindMemory(to: UInt8.self).baseAddress!, count: data.count)
    }

    return UInt32(data.count)
}

@_cdecl("llcas_digest_print")
public func llcas_digest_print(
    _ cas: UnsafeMutableRawPointer?,
    _ digest: llcas_digest_t,
    _ printed_id: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    guard let data = digest.data, digest.size > 0 else {
        error?.pointee = strdup("Invalid digest data")
        return true
    }

    let buffer = UnsafeBufferPointer(start: data, count: digest.size)
    let hexString = Data(buffer).hexString
    printed_id?.pointee = strdup(hexString)
    return false
}

@_cdecl("llcas_cas_get_objectid")
public func llcas_cas_get_objectid(
    _ cas: UnsafeMutableRawPointer?,
    _ digest: llcas_digest_t,
    _ p_id: UnsafeMutablePointer<llcas_objectid_t>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    guard let data = digest.data, digest.size > 0 else {
        error?.pointee = strdup("Invalid digest")
        return true
    }

    let buffer = UnsafeBufferPointer(start: data, count: digest.size)
    let hexString = Data(buffer).hexString

    // Store the string as opaque data
    let ptr = strdup(hexString)
    p_id?.pointee = llcas_objectid_t(opaque: UInt64(UInt(bitPattern: ptr)))

    return false
}

@_cdecl("llcas_objectid_get_digest")
public func llcas_objectid_get_digest(
    _ cas: UnsafeMutableRawPointer?,
    _ objectid: llcas_objectid_t
) -> llcas_digest_t {
    let ptr = UnsafeMutablePointer<CChar>(bitPattern: UInt(objectid.opaque))
    guard let ptr else {
        return llcas_digest_t(data: nil, size: 0)
    }

    let hexString = String(cString: ptr)
    guard let data = Data(hexString: hexString) else {
        return llcas_digest_t(data: nil, size: 0)
    }

    // Allocate and copy
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    data.withUnsafeBytes { bytes in
        buffer.initialize(from: bytes.bindMemory(to: UInt8.self).baseAddress!, count: data.count)
    }

    return llcas_digest_t(data: buffer, size: data.count)
}

@_cdecl("llcas_cas_contains_object")
public func llcas_cas_contains_object(
    _ cas: UnsafeMutableRawPointer?,
    _ objectid: llcas_objectid_t,
    _ globally: Bool,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> llcas_lookup_result_t {
    let ptr = UnsafeMutablePointer<CChar>(bitPattern: UInt(objectid.opaque))
    guard let ptr else {
        error?.pointee = strdup("Invalid object ID")
        return LLCAS_LOOKUP_RESULT_ERROR
    }

    let hashString = String(cString: ptr)
    let dataID = DataID(hash: hashString)

    return runAsyncAndWait {
        let exists = await withRemoteCAS(error) { cas in
            try await cas.contains(id: dataID)
        }
        return (exists == true) ? LLCAS_LOOKUP_RESULT_SUCCESS : LLCAS_LOOKUP_RESULT_NOTFOUND
    }
}

// Helper to bridge async Swift to sync C functions
// Note: This blocks the calling thread, which is acceptable for C bridge functions
// that are called from swift-build's worker threads
private func runAsyncAndWait<T>(_ operation: @escaping () async -> T) -> T {
    nonisolated(unsafe) var result: T!
    let semaphore = DispatchSemaphore(value: 0)

    let task = Task {
        result = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    _ = task // Keep task alive
    return result
}

@_cdecl("llcas_cas_load_object")
public func llcas_cas_load_object(
    _ cas: UnsafeMutableRawPointer?,
    _ objectid: llcas_objectid_t,
    _ p_loaded: UnsafeMutablePointer<llcas_loaded_object_t>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> llcas_lookup_result_t {
    let ptr = UnsafeMutablePointer<CChar>(bitPattern: UInt(objectid.opaque))
    guard let ptr else {
        error?.pointee = strdup("Invalid object ID")
        return LLCAS_LOOKUP_RESULT_ERROR
    }

    let hashString = String(cString: ptr)
    let dataID = DataID(hash: hashString)

    return runAsyncAndWait {
        let object = await withRemoteCAS(error) { cas -> CASObject? in
            try await cas.load(id: dataID)
        }

        guard let unwrappedObject = object else {
            return LLCAS_LOOKUP_RESULT_NOTFOUND
        }

        let storedID = await objectStore.store(object: unwrappedObject!)
        p_loaded?.pointee = llcas_loaded_object_t(opaque: storedID)
        return LLCAS_LOOKUP_RESULT_SUCCESS
    }
}

@_cdecl("llcas_cas_load_object_async")
public func llcas_cas_load_object_async(
    _ cas: UnsafeMutableRawPointer?,
    _ objectid: llcas_objectid_t,
    _ ctx_cb: UnsafeMutableRawPointer?,
    _ callback: llcas_cas_load_object_cb?,
    _ cancel_tok: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) {
    let ptr = UnsafeMutablePointer<CChar>(bitPattern: UInt(objectid.opaque))
    guard let ptr, let callback else {
        callback?(ctx_cb, LLCAS_LOOKUP_RESULT_ERROR, llcas_loaded_object_t(opaque: 0), strdup("Invalid parameters"))
        return
    }

    let hashString = String(cString: ptr)
    let dataID = DataID(hash: hashString)

    nonisolated(unsafe) let callbackCapture = callback
    nonisolated(unsafe) let ctxCapture = ctx_cb

    let _ = Task {
        var errorStr: UnsafeMutablePointer<CChar>?
        let object = await withRemoteCAS(&errorStr) { cas -> CASObject? in
            try await cas.load(id: dataID)
        }

        if let unwrappedObject = object {
            let storedID = await objectStore.store(object: unwrappedObject!)
            callbackCapture(ctxCapture, LLCAS_LOOKUP_RESULT_SUCCESS, llcas_loaded_object_t(opaque: storedID), nil)
        } else if errorStr != nil {
            callbackCapture(ctxCapture, LLCAS_LOOKUP_RESULT_ERROR, llcas_loaded_object_t(opaque: 0), errorStr)
        } else {
            callbackCapture(ctxCapture, LLCAS_LOOKUP_RESULT_NOTFOUND, llcas_loaded_object_t(opaque: 0), nil)
        }
    }
}

@_cdecl("llcas_cas_store_object")
public func llcas_cas_store_object(
    _ cas: UnsafeMutableRawPointer?,
    _ data: llcas_data_t,
    _ refs: UnsafePointer<llcas_objectid_t>?,
    _ refs_count: Int,
    _ p_id: UnsafeMutablePointer<llcas_objectid_t>?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    guard let dataPtr = data.data else {
        error?.pointee = strdup("Invalid data")
        return true
    }

    let buffer = UnsafeRawBufferPointer(start: dataPtr, count: data.size)
    let byteString = ByteString(Data(buffer))

    var refIDs: [DataID] = []
    if let refs, refs_count > 0 {
        for i in 0..<refs_count {
            let refPtr = UnsafeMutablePointer<CChar>(bitPattern: UInt(refs[i].opaque))
            if let refPtr {
                let hashString = String(cString: refPtr)
                refIDs.append(DataID(hash: hashString))
            }
        }
    }

    let object = CASObject(data: byteString, refs: refIDs)

    return runAsyncAndWait {
        let resultID = await withRemoteCAS(error) { cas in
            try await cas.store(object: object)
        }

        if let resultID {
            let ptr = strdup(resultID.hash)
            p_id?.pointee = llcas_objectid_t(opaque: UInt64(UInt(bitPattern: ptr)))
            return false
        } else {
            return true
        }
    }
}

@_cdecl("llcas_loaded_object_get_data")
public func llcas_loaded_object_get_data(
    _ cas: UnsafeMutableRawPointer?,
    _ loaded: llcas_loaded_object_t
) -> llcas_data_t {
    return runAsyncAndWait {
        if let object = await objectStore.getObject(loaded.opaque) {
            let data = object.data.bytes
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 8)
            data.withUnsafeBytes { bytes in
                buffer.copyMemory(from: bytes.baseAddress!, byteCount: data.count)
            }
            return llcas_data_t(data: buffer, size: data.count)
        } else {
            return llcas_data_t(data: nil, size: 0)
        }
    }
}

@_cdecl("llcas_loaded_object_get_refs")
public func llcas_loaded_object_get_refs(
    _ cas: UnsafeMutableRawPointer?,
    _ loaded: llcas_loaded_object_t
) -> llcas_object_refs_t {
    return runAsyncAndWait {
        if let refs = await objectStore.getRefs(loaded.opaque) {
            // Store ref count in opaque_b, object ID in opaque_e
            return llcas_object_refs_t(opaque_b: UInt64(refs.count), opaque_e: loaded.opaque)
        } else {
            return llcas_object_refs_t(opaque_b: 0, opaque_e: 0)
        }
    }
}

@_cdecl("llcas_object_refs_get_count")
public func llcas_object_refs_get_count(
    _ cas: UnsafeMutableRawPointer?,
    _ refs: llcas_object_refs_t
) -> Int {
    return Int(refs.opaque_b)
}

@_cdecl("llcas_object_refs_get_id")
public func llcas_object_refs_get_id(
    _ cas: UnsafeMutableRawPointer?,
    _ refs: llcas_object_refs_t,
    _ index: Int
) -> llcas_objectid_t {
    return runAsyncAndWait {
        if let refArray = await objectStore.getRefs(refs.opaque_e), index < refArray.count {
            let ptr = strdup(refArray[index].hash)
            return llcas_objectid_t(opaque: UInt64(UInt(bitPattern: ptr)))
        } else {
            return llcas_objectid_t(opaque: 0)
        }
    }
}

@_cdecl("llcas_actioncache_get_for_digest")
public func llcas_actioncache_get_for_digest(
    _ cas: UnsafeMutableRawPointer?,
    _ key: llcas_digest_t,
    _ p_value: UnsafeMutablePointer<llcas_objectid_t>?,
    _ globally: Bool,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> llcas_lookup_result_t {
    guard let keyData = key.data, key.size > 0 else {
        error?.pointee = strdup("Invalid key digest")
        return LLCAS_LOOKUP_RESULT_ERROR
    }

    let buffer = UnsafeBufferPointer(start: keyData, count: key.size)
    let keyID = DataID(hash: Data(buffer).hexString)

    return runAsyncAndWait {
        let valueID = await withRemoteCAS(error) { cas -> DataID? in
            try await cas.lookupCachedObject(for: keyID)
        }

        guard let unwrappedValueID = valueID else {
            return LLCAS_LOOKUP_RESULT_NOTFOUND
        }

        let hashStr: String = unwrappedValueID!.hash
        let ptr = strdup(hashStr)
        p_value?.pointee = llcas_objectid_t(opaque: UInt64(UInt(bitPattern: ptr)))
        return LLCAS_LOOKUP_RESULT_SUCCESS
    }
}

@_cdecl("llcas_actioncache_get_for_digest_async")
public func llcas_actioncache_get_for_digest_async(
    _ cas: UnsafeMutableRawPointer?,
    _ key: llcas_digest_t,
    _ globally: Bool,
    _ ctx_cb: UnsafeMutableRawPointer?,
    _ callback: llcas_actioncache_get_cb?,
    _ cancel_tok: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) {
    guard let keyData = key.data, key.size > 0, let callback else {
        callback?(ctx_cb, LLCAS_LOOKUP_RESULT_ERROR, llcas_objectid_t(opaque: 0), strdup("Invalid parameters"))
        return
    }

    let buffer = UnsafeBufferPointer(start: keyData, count: key.size)
    let keyID = DataID(hash: Data(buffer).hexString)

    let _ = Task {
        var errorStr: UnsafeMutablePointer<CChar>?
        let valueID = await withRemoteCAS(&errorStr) { cas -> DataID? in
            try await cas.lookupCachedObject(for: keyID)
        }

        if let unwrappedValueID = valueID {
            let hashStr: String = unwrappedValueID!.hash
            let ptr = strdup(hashStr)
            callback(ctx_cb, LLCAS_LOOKUP_RESULT_SUCCESS, llcas_objectid_t(opaque: UInt64(UInt(bitPattern: ptr))), nil)
        } else if errorStr != nil {
            callback(ctx_cb, LLCAS_LOOKUP_RESULT_ERROR, llcas_objectid_t(opaque: 0), errorStr)
        } else {
            callback(ctx_cb, LLCAS_LOOKUP_RESULT_NOTFOUND, llcas_objectid_t(opaque: 0), nil)
        }
    }
}

@_cdecl("llcas_actioncache_put_for_digest")
public func llcas_actioncache_put_for_digest(
    _ cas: UnsafeMutableRawPointer?,
    _ key: llcas_digest_t,
    _ value: llcas_objectid_t,
    _ globally: Bool,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Bool {
    guard let keyData = key.data, key.size > 0 else {
        error?.pointee = strdup("Invalid key digest")
        return true
    }

    let valuePtr = UnsafeMutablePointer<CChar>(bitPattern: UInt(value.opaque))
    guard let valuePtr else {
        error?.pointee = strdup("Invalid value object ID")
        return true
    }

    let keyBuffer = UnsafeBufferPointer<UInt8>(start: keyData, count: key.size)
    let keyID = DataID(hash: Data(keyBuffer).hexString)
    let valueID = DataID(hash: String(cString: valuePtr))

    return runAsyncAndWait {
        let success = await withRemoteCAS(error) { cas in
            try await cas.cache(objectID: valueID, forKeyID: keyID)
            return true
        }
        return success != true
    }
}

@_cdecl("llcas_actioncache_put_for_digest_async")
public func llcas_actioncache_put_for_digest_async(
    _ cas: UnsafeMutableRawPointer?,
    _ key: llcas_digest_t,
    _ value: llcas_objectid_t,
    _ globally: Bool,
    _ ctx_cb: UnsafeMutableRawPointer?,
    _ callback: llcas_actioncache_put_cb?,
    _ cancel_tok: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) {
    guard let keyData = key.data, key.size > 0, let callback else {
        callback?(ctx_cb, true, strdup("Invalid parameters"))
        return
    }

    let valuePtr = UnsafeMutablePointer<CChar>(bitPattern: UInt(value.opaque))
    guard let valuePtr else {
        callback(ctx_cb, true, strdup("Invalid value object ID"))
        return
    }

    let keyBuffer = UnsafeBufferPointer<UInt8>(start: keyData, count: key.size)
    let keyID = DataID(hash: Data(keyBuffer).hexString)
    let valueID = DataID(hash: String(cString: valuePtr))

    let _ = Task {
        var errorStr: UnsafeMutablePointer<CChar>?
        let success = await withRemoteCAS(&errorStr) { cas in
            try await cas.cache(objectID: valueID, forKeyID: keyID)
            return true
        }

        callback(ctx_cb, success != true, errorStr)
    }
}

// MARK: - Data Extension

private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}