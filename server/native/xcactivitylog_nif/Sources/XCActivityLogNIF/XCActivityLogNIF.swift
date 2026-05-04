import Foundation
import Path
import XCActivityLogParser

// Heap-allocated holder for the parse result. The NIF may abandon the wait on
// timeout and return before the Task finishes, so the result storage cannot
// live on the stack — ARC keeps the box alive as long as either side holds a
// reference. The semaphore provides the happens-before edge for safe reads.
private final class ParseResultBox: @unchecked Sendable {
    var value: Result<BuildData, Error>?
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

    let box = ParseResultBox()
    let semaphore = DispatchSemaphore(value: 0)

    let task = Task { @Sendable in
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
        box.value = outcome
        semaphore.signal()
    }
    // Propagate cancellation on every exit path (timeout, success, throw).
    // The current parser doesn't check Task.isCancelled, so this is a no-op
    // today, but it makes the structured intent explicit and future-proofs
    // the handoff if a parser starts honoring cancellation.
    defer { task.cancel() }

    let deadline = DispatchTime.now() + .seconds(parseTimeoutSeconds)
    if semaphore.wait(timeout: deadline) == .timedOut {
        let error = NSError(
            domain: "XCActivityLogNIF",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "parse timed out after \(parseTimeoutSeconds)s"]
        )
        return writeError(error, outputPtr: outputPtr, outputLen: outputLen)
    }

    switch box.value! {
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
