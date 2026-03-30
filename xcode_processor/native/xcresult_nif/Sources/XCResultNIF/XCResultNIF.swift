import Foundation
import XCResultParser

@_cdecl("parse_xcresult")
public func parseXCResult(
    _ pathPtr: UnsafePointer<CChar>,
    _ rootDirPtr: UnsafePointer<CChar>,
    _ outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let path = String(cString: pathPtr)
    let rootDir = String(cString: rootDirPtr)

    nonisolated(unsafe) var result: Result<TestSummary, Error> = .failure(
        XCResultParserError.xcresulttoolFailed("NIF task did not complete")
    )
    let semaphore = DispatchSemaphore(value: 0)

    Task { @Sendable in
        do {
            let parsed = try await XCResultParser().parse(
                xcresultPath: path,
                rootDirectory: rootDir
            )
            result = .success(parsed)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    let timeout = semaphore.wait(timeout: .now() + .seconds(600))
    if timeout == .timedOut {
        result = .failure(XCResultParserError.xcresulttoolFailed("NIF task timed out after 600 seconds"))
    }

    switch result {
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
