import Foundation
import Path
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
        XCResultParserError.failedToParseOutput(try! AbsolutePath(validating: path))
    )
    let semaphore = DispatchSemaphore(value: 0)

    Task { @Sendable in
        do {
            let xcresultPath = try AbsolutePath(validating: path)
            let rootDirectory = try AbsolutePath(validating: rootDir)
            guard let parsed = try await XCResultParser().parse(
                path: xcresultPath,
                rootDirectory: rootDirectory
            ) else {
                result = .failure(XCResultParserError.failedToParseOutput(xcresultPath))
                semaphore.signal()
                return
            }
            let quarantinedTests = readQuarantinedTests(at: xcresultPath)
            result = .success(parsed.applyingQuarantine(quarantinedTests))
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    let timeout = semaphore.wait(timeout: .now() + .seconds(600))
    if timeout == .timedOut {
        result = .failure(XCResultParserError.failedToParseOutput(try! AbsolutePath(validating: path)))
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

private func readQuarantinedTests(at xcresultPath: AbsolutePath) -> [QuarantinedTestIdentifier] {
    let url = URL(fileURLWithPath: xcresultPath.appending(component: "quarantined_tests.json").pathString)
    guard let data = try? Data(contentsOf: url),
          let entries = try? JSONDecoder().decode([QuarantinedTestIdentifier].self, from: data)
    else { return [] }
    return entries
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
