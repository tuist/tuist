import Foundation
import XCActivityLogParser

@_cdecl("parse_xcactivitylog")
public func parseXCActivityLog(
    _ pathPtr: UnsafePointer<CChar>,
    _ casMetadataPathPtr: UnsafePointer<CChar>,
    _ cacheUploadEnabled: Int32,
    _ outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let path = String(cString: pathPtr)
    let casMetadataPath = String(cString: casMetadataPathPtr)
    let url = URL(fileURLWithPath: path)

    do {
        let parsed = try XCActivityLogParser.parse(
            xcactivitylogURL: url,
            casMetadataPath: casMetadataPath,
            cacheUploadEnabled: cacheUploadEnabled != 0
        )
        let jsonData = try JSONEncoder().encode(parsed)

        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: jsonData.count)
        jsonData.withUnsafeBytes { rawBytes in
            buffer.initialize(from: rawBytes.bindMemory(to: CChar.self).baseAddress!, count: jsonData.count)
        }
        outputPtr.pointee = buffer
        outputLen.pointee = Int32(jsonData.count)
        return 0
    } catch {
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
}
