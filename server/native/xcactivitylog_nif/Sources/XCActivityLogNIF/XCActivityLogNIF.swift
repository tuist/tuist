import Foundation
import Path
import XCActivityLogParser

// Heap-allocated, lock-protected handoff between the parsing Task and the NIF
// thread. Reference-counted so it stays alive as long as either side holds it
// — required because we may abandon the wait on timeout and return from the
// NIF while the Task is still running. Mutators are synchronous so the lock
// is never held across a suspension point.
private final class ParseHandoff: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<BuildData, Error>?
    private var _abandoned = false

    // Returns true if the NIF thread is still waiting (and the result was
    // stored); false if it timed out and the Task should drop its outcome.
    func deliverIfWaiting(_ outcome: Result<BuildData, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_abandoned else { return false }
        _result = outcome
        return true
    }

    func abandon() {
        lock.lock()
        _abandoned = true
        lock.unlock()
    }

    func takeResult() -> Result<BuildData, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return _result
    }
}

// Hard cap on a single parse. The Swift Task runs on the cooperative pool,
// not the BEAM dirty scheduler we're called from, so timing out here lets the
// dirty scheduler thread go even when the parser itself is wedged on a
// pathological xcactivitylog. Set below the Oban worker's wall-time limit so
// the NIF returns a structured error before Oban kills the process.
private let parseTimeoutSeconds = 240

@_cdecl("parse_xcactivitylog")
public func parseXCActivityLog(
    _ pathPtr: UnsafePointer<CChar>,
    _ casAnalyticsDbPathPtr: UnsafePointer<CChar>,
    _ legacyCASMetadataPathPtr: UnsafePointer<CChar>,
    _ cacheUploadEnabled: Int32,
    _ outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let path = String(cString: pathPtr)
    let casAnalyticsDbPath = String(cString: casAnalyticsDbPathPtr)
    let legacyCASMetadataPath = String(cString: legacyCASMetadataPathPtr)
    let url = URL(fileURLWithPath: path)

    let handoff = ParseHandoff()
    let semaphore = DispatchSemaphore(value: 0)

    Task { @Sendable in
        let outcome: Result<BuildData, Error>
        do {
            let parsed = try await XCActivityLogParser().parse(
                xcactivitylogURL: url,
                casAnalyticsDatabasePath: try AbsolutePath(validating: casAnalyticsDbPath),
                legacyCASMetadataPath: try AbsolutePath(validating: legacyCASMetadataPath)
            )
            outcome = .success(parsed)
        } catch {
            outcome = .failure(error)
        }

        if handoff.deliverIfWaiting(outcome) {
            semaphore.signal()
        }
    }

    let deadline = DispatchTime.now() + .seconds(parseTimeoutSeconds)
    if semaphore.wait(timeout: deadline) == .timedOut {
        handoff.abandon()
        let error = NSError(
            domain: "XCActivityLogNIF",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "parse timed out after \(parseTimeoutSeconds)s"]
        )
        return writeError(error, outputPtr: outputPtr, outputLen: outputLen)
    }

    guard let result = handoff.takeResult() else {
        let error = NSError(
            domain: "XCActivityLogNIF",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "parse handoff missing result"]
        )
        return writeError(error, outputPtr: outputPtr, outputLen: outputLen)
    }

    switch result {
    case let .success(parsed):
        do {
            let jsonData = try JSONEncoder().encode(parsed)
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: jsonData.count)
            jsonData.withUnsafeBytes { rawBytes in
                buffer.initialize(from: rawBytes.bindMemory(to: CChar.self).baseAddress!, count: jsonData.count)
            }
            outputPtr.pointee = buffer
            outputLen.pointee = Int32(jsonData.count)
            return 0
        } catch {
            return writeError(error, outputPtr: outputPtr, outputLen: outputLen)
        }
    case let .failure(error):
        return writeError(error, outputPtr: outputPtr, outputLen: outputLen)
    }
}

private func writeError(
    _ error: Error,
    outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let errorJSON = "{\"error\": \"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    let data = Array(errorJSON.utf8)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
    for (i, byte) in data.enumerated() {
        buffer[i] = CChar(bitPattern: byte)
    }
    outputPtr.pointee = buffer
    outputLen.pointee = Int32(data.count)
    return 1
}
