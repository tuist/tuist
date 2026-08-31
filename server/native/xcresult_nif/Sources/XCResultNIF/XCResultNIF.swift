import Foundation
import os
import Path
import XCResultParser

/// Outcome of a parse in the form the C boundary carries.
///
/// Failures are reduced to their message because that is all `parse_xcresult`
/// writes back, and it keeps the value `Sendable` so it can cross from the
/// parse task to the thread blocked on it.
private enum ParseOutcome: Sendable {
    case parsed(TestSummary)
    case failed(String)
}

/// Seconds a parse may run before it cancels itself.
private let timeoutSeconds = 600

/// Parses abandoned at the outer deadline, for the life of this process.
///
/// Reaching that deadline means the parse did not unwind when cancelled,
/// so returning leaves its task, its `CommandRunner` permit and its
/// `xcresulttool` child running with no handle left to reach them. The
/// slot the parse occupied is gone until the OS process restarts, and
/// nothing in the BEAM's own accounting records that: a leaked slot is
/// invisible to `erlang:memory/0`, to the scheduler counters and to
/// every Oban gauge until throughput has already reached zero.
///
/// Counting them is what makes the loss measurable from Elixir, and
/// what lets the node decide it has no capacity left to lose.
private let abandonedParses = OSAllocatedUnfairLock<Int32>(initialState: 0)

/// Number of parses this process has abandoned at the outer deadline.
@_cdecl("xcresult_abandoned_parses")
public func xcresultAbandonedParses() -> Int32 {
    abandonedParses.withLock { $0 }
}

/// Seconds a cancelled parse is given to unwind before the caller gives up on
/// it. Cancellation reaches the `xcresulttool`/`sips` child through Command's
/// `continuation.onTermination`, which terminates the process; a child that
/// ignores it would otherwise hold this thread for the life of the BEAM.
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

    let outcome = OSAllocatedUnfairLock<ParseOutcome?>(initialState: nil)
    let semaphore = DispatchSemaphore(value: 0)

    let task = Task {
        let value: ParseOutcome
        do {
            let parsed = try await parse(path: path, rootDir: rootDir, timeout: timeoutSeconds)
            value = .parsed(parsed)
        } catch {
            value = .failed(error.localizedDescription)
        }
        outcome.withLock { $0 = value }
        semaphore.signal()
    }

    // The parse cancels itself at `timeoutSeconds` and the task group it runs
    // in cannot return until that cancellation has been awaited, so reaching
    // this deadline means the child never honoured it. Nothing is read from
    // `outcome` on that path, so a late write cannot race the value returned.
    let deadline = DispatchTime.now() + .seconds(timeoutSeconds + cancellationGraceSeconds)
    guard semaphore.wait(timeout: deadline) == .success else {
        task.cancel()
        abandonedParses.withLock { $0 += 1 }
        return write(
            timedOutMessage(path: path, seconds: timeoutSeconds),
            outputPtr: outputPtr,
            outputLen: outputLen
        )
    }

    guard let value = outcome.withLock({ $0 }) else {
        return write(failedToParseMessage(path: path), outputPtr: outputPtr, outputLen: outputLen)
    }

    switch value {
    case let .parsed(parsed):
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
            return write(error.localizedDescription, outputPtr: outputPtr, outputLen: outputLen)
        }
    case let .failed(message):
        return write(message, outputPtr: outputPtr, outputLen: outputLen)
    }
}

/// Runs the parse against a deadline, racing it with a sleeping sibling.
///
/// Losing the race cancels the winner's sibling, and the group cannot return
/// until every child has been awaited, so a timed-out parse is torn down
/// before the caller sees the error rather than left running with a
/// `CommandRunner` process-limiter permit and a temp directory the worker is
/// about to delete.
private func parse(path: String, rootDir: String, timeout: Int) async throws -> TestSummary {
    let xcresultPath = try AbsolutePath(validating: path)
    let rootDirectory = try AbsolutePath(validating: rootDir)

    return try await withThrowingTaskGroup(of: TestSummary?.self) { group in
        group.addTask {
            // The server worker passes its per-run temp dir as rootDir and
            // removes it wholesale once the run is processed, so it's also
            // a directory we can export attachments into — point them there
            // so the worker's cleanup reclaims them instead of leaking them
            // in a process-wide temp dir.
            try await XCResultParser().parse(
                path: xcresultPath,
                rootDirectory: rootDirectory,
                attachmentsDirectory: rootDirectory
            )
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw XCResultParserError.timedOut(xcresultPath, seconds: timeout)
        }

        defer { group.cancelAll() }

        guard let finished = try await group.next(), let parsed = finished else {
            throw XCResultParserError.failedToParseOutput(xcresultPath)
        }
        return parsed
    }
}

/// Mirror `XCResultParserError`'s descriptions, for the paths where no
/// validated `AbsolutePath` is at hand to build the error itself from.
private func timedOutMessage(path: String, seconds: Int) -> String {
    "xcresult parsing timed out after \(seconds)s at \(path)"
}

private func failedToParseMessage(path: String) -> String {
    "Failed to parse xcresult output at \(path)"
}

private func write(
    _ message: String,
    outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let errorJSON = "{\"error\": \"\(message.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    let data = Array(errorJSON.utf8)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
    for (i, byte) in data.enumerated() {
        buffer[i] = CChar(bitPattern: byte)
    }
    outputPtr.pointee = buffer
    outputLen.pointee = Int32(data.count)
    return 1
}
