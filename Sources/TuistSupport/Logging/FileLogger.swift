import Foundation
import TSCBasic

public struct FileLogger: TextOutputStream {
    enum FileHandlerOutputStream: Error {
        case couldNotCreateFile
    }

    private let fileHandle: FileHandle
    let encoding: String.Encoding

    public init(path: AbsolutePath, encoding: String.Encoding = .utf8) throws {
        if !FileManager.default.fileExists(atPath: path.url.path) {
            guard FileManager.default.createFile(atPath: path.url.path, contents: nil, attributes: nil) else {
                throw FileHandlerOutputStream.couldNotCreateFile
            }
        }

        let fileHandle = try FileHandle(forWritingTo: path.url)
        fileHandle.seekToEndOfFile()
        self.fileHandle = fileHandle
        self.encoding = encoding
    }

    public mutating func write(_ string: String) {
        if let data = string.data(using: encoding) {
            fileHandle.write(data)
        }
    }
}
