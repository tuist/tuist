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
        return writeMessage("parse timed out after \(parseTimeoutSeconds)s", outputPtr: outputPtr, outputLen: outputLen)
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
            return writeMessage(error.localizedDescription, outputPtr: outputPtr, outputLen: outputLen)
        }
    case let .failure(error):
        return writeMessage(error.localizedDescription, outputPtr: outputPtr, outputLen: outputLen)
    }
}

// Writes a plain UTF-8 error message into the output buffer. The C bridge
// surfaces the bytes as an Erlang binary in `{:error, <<message>>}`, so a
// raw string is enough — no JSON wrapping needed on this path.
private func writeMessage(
    _ message: String,
    outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let bytes = Array(message.utf8)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: max(bytes.count, 1))
    for (i, byte) in bytes.enumerated() {
        buffer[i] = CChar(bitPattern: byte)
    }
    outputPtr.pointee = buffer
    outputLen.pointee = Int32(bytes.count)
    return 1
}
