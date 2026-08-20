import Foundation
import Path
import XCResultParser

/// Errors raised at the NIF boundary, where a path that failed `AbsolutePath`
/// validation leaves nothing to build an `XCResultParserError` from. The
/// messages mirror their `XCResultParserError` counterparts so a given failure
/// reads the same whichever type carries it.
enum XCResultNIFError: LocalizedError {
    case timedOut(path: String, seconds: Int)
    case failedToParseOutput(path: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(path, seconds):
            return "xcresult parsing timed out after \(seconds)s at \(path)"
        case let .failedToParseOutput(path):
            return "Failed to parse xcresult output at \(path)"
        }
    }
}

/// Carries the parse outcome from the Task that produces it to the NIF thread
/// that reads it.
///
/// A parse that outlives its timeout keeps writing here after the NIF has
/// returned, so the storage outlives the call (the Task holds the only
/// remaining reference) and every access is serialised. Writing the outcome
/// through `finalize` in the same critical section it is read from keeps a
/// late write from replacing the value the caller is about to receive.
private final class ParseResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<TestSummary, Error>?

    func store(_ value: Result<TestSummary, Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func value() -> Result<TestSummary, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    func finalize(with value: Result<TestSummary, Error>) -> Result<TestSummary, Error> {
        lock.lock()
        defer { lock.unlock() }
        result = value
        return value
    }
}

/// Seconds a parse may run before it is cancelled.
private let timeoutSeconds = 600

/// Seconds a cancelled parse is given to unwind before the NIF returns.
///
/// Cancellation reaches the `xcresulttool`/`sips` child through Command's
/// `continuation.onTermination`, which terminates the process. Waiting for that
/// to land keeps the child from surviving as an orphan holding a
/// `CommandRunner` process-limiter permit for the lifetime of the BEAM, and
/// keeps it from writing into the temp directory the worker deletes next.
private let cancellationGraceSeconds = 30

@_cdecl("parse_xcresult")
public func parseXCResult(
    _ pathPtr: UnsafePointer<CChar>,
    _ rootDirPtr: UnsafePointer<CChar>,
    _ outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let path = String(cString: pathPtr)
    let rootDir = String(cString: rootDirPtr)

    let box = ParseResultBox()
    let semaphore = DispatchSemaphore(value: 0)

    let task = Task { @Sendable in
        defer { semaphore.signal() }

        do {
            let xcresultPath = try AbsolutePath(validating: path)
            let rootDirectory = try AbsolutePath(validating: rootDir)
            // The server worker passes its per-run temp dir as rootDir and
            // removes it wholesale once the run is processed, so it's also
            // a directory we can export attachments into — point them there
            // so the worker's cleanup reclaims them instead of leaking them
            // in a process-wide temp dir.
            guard let parsed = try await XCResultParser().parse(
                path: xcresultPath,
                rootDirectory: rootDirectory,
                attachmentsDirectory: rootDirectory
            ) else {
                box.store(.failure(XCResultParserError.failedToParseOutput(xcresultPath)))
                return
            }
            box.store(.success(parsed))
        } catch {
            box.store(.failure(error))
        }
    }

    let outcome: Result<TestSummary, Error>
    if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
        task.cancel()
        _ = semaphore.wait(timeout: .now() + .seconds(cancellationGraceSeconds))
        outcome = box.finalize(with: .failure(timedOutError(path: path, seconds: timeoutSeconds)))
    } else {
        outcome = box.value() ?? .failure(XCResultNIFError.failedToParseOutput(path: path))
    }

    switch outcome {
    case let .success(parsed):
        do {
            let jsonData = try JSONEncoder().encode(parsed)
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: jsonData.count)
            jsonData.withUnsafeBytes { rawBytes in
                buffer.initialize(
                    from: rawBytes.bindMemory(to: CChar.self).baseAddress!,
                    count: jsonData.count
                )
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

private func timedOutError(path: String, seconds: Int) -> Error {
    guard let xcresultPath = try? AbsolutePath(validating: path) else {
        return XCResultNIFError.timedOut(path: path, seconds: seconds)
    }
    return XCResultParserError.timedOut(xcresultPath, seconds: seconds)
}

private func writeError(
    _ error: Error,
    outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let errorJSON =
        "{\"error\": \"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    let data = Array(errorJSON.utf8)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
    for (i, byte) in data.enumerated() {
        buffer[i] = CChar(bitPattern: byte)
    }
    outputPtr.pointee = buffer
    outputLen.pointee = Int32(data.count)
    return 1
}
