import Foundation

extension FileHandle {
    /// Returns the current offset in the file.
    var currentOffset: UInt64 {
        offsetInFile
    }

    /// Seeks to a specific file offset.
    func seek(to offset: UInt64) {
        seek(toFileOffset: offset)
    }

    /// Reads a value of type `T` from the file handle.
    /// - Returns: The value `T` loaded from the next `MemoryLayout<T>.size` bytes.
    func read<T>() -> T {
        let data = readData(ofLength: MemoryLayout<T>.size)
        return data.withUnsafeBytes { $0.load(as: T.self) }
    }

    /// Reads a string of a specified length using ASCII encoding.
    /// - Parameter length: The number of bytes to read.
    /// - Returns: A `String` if decoding succeeds, otherwise `nil`.
    func readString(ofLength length: Int) -> String? {
        let data = readData(ofLength: length)
        return String(data: data, encoding: .ascii)
    }
}
