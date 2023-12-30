import Foundation
import TSCBasic

public struct FileLogger: TextOutputStream {
    enum FileHandlerOutputStream: Error {
        case couldNotCreateFile
    }

    private let fileHandle: FileHandle
    let encoding: String.Encoding

    public init(path: AbsolutePath, encoding: String.Encoding = .utf8) throws {
        if !FileHandler.shared.exists(path) {
            if !FileHandler.shared.exists(path.parentDirectory) {
                try FileHandler.shared.createFolder(path.parentDirectory)
            }
            try FileHandler.shared.touch(path)
        }

        let fileHandle = try FileHandle(forWritingTo: path.url)
        fileHandle.seekToEndOfFile()
        self.fileHandle = fileHandle
        self.encoding = encoding
    }

    public func write(_ string: String) {
        if let data = string.data(using: encoding) {
            fileHandle.write(data)
        }
    }
}
