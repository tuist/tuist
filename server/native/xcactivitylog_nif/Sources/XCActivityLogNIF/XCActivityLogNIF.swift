import Foundation
import Path
import XCActivityLogParser

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

    // nonisolated(unsafe) is needed because the Swift 6 concurrency checker doesn't understand
    // that the DispatchSemaphore guarantees sequential access (write before signal, read after wait).
    nonisolated(unsafe) var result: Result<BuildData, Error>!
    let semaphore = DispatchSemaphore(value: 0)

    Task { @Sendable in
        do {
            let parsed = try await XCActivityLogParser().parse(
                xcactivitylogURL: url,
                casAnalyticsDatabasePath: try AbsolutePath(validating: casAnalyticsDbPath),
                legacyCASMetadataPath: try AbsolutePath(validating: legacyCASMetadataPath)
            )
            result = .success(parsed)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()

    switch result! {
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
