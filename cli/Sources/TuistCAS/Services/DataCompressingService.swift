import Foundation
import libzstd
import Logging
import Mockable

@Mockable
protocol DataCompressingServicing: Sendable {
    func compress(_ data: Data) async throws -> Data
    func decompress(_ data: Data) async throws -> Data
}

struct DataCompressingService: DataCompressingServicing {
    @concurrent
    func compress(_ data: Data) async throws -> Data {
        let startTime = ProcessInfo.processInfo.systemUptime

        let maxCompressedSize = ZSTD_compressBound(data.count)
        var compressedBuffer = [UInt8](repeating: 0, count: maxCompressedSize)

        let compressedSize = data.withUnsafeBytes { srcBytes in
            compressedBuffer.withUnsafeMutableBytes { dstBytes in
                ZSTD_compress(
                    dstBytes.baseAddress,
                    maxCompressedSize,
                    srcBytes.baseAddress,
                    data.count,
                    1 // compression level
                )
            }
        }

        guard ZSTD_isError(compressedSize) == 0 else {
            throw DataCompressionError.compressionFailed(errorCode: Int(compressedSize))
        }

        let compressedData = Data(compressedBuffer.prefix(compressedSize))
        let duration = ProcessInfo.processInfo.systemUptime - startTime
        Logger.current
            .debug(
                "DataCompressingService compressed data from \(data.count) to \(compressedData.count) bytes in \(String(format: "%.3f", duration))s"
            )

        return compressedData
    }

    @concurrent
    func decompress(_ data: Data) async throws -> Data {
        let startTime = ProcessInfo.processInfo.systemUptime

        // Get the decompressed size first
        let decompressedSize = data.withUnsafeBytes { bytes in
            ZSTD_getFrameContentSize(bytes.baseAddress, data.count)
        }

        guard decompressedSize != ZSTD_CONTENTSIZE_ERROR, decompressedSize != ZSTD_CONTENTSIZE_UNKNOWN else {
            throw DataCompressionError.cannotDetermineDecompressedSize
        }

        var decompressedBuffer = [UInt8](repeating: 0, count: Int(decompressedSize))

        let actualDecompressedSize = data.withUnsafeBytes { srcBytes in
            decompressedBuffer.withUnsafeMutableBytes { dstBytes in
                ZSTD_decompress(
                    dstBytes.baseAddress,
                    Int(decompressedSize),
                    srcBytes.baseAddress,
                    data.count
                )
            }
        }

        guard ZSTD_isError(actualDecompressedSize) == 0 else {
            throw DataCompressionError.decompressionFailed(errorCode: Int(actualDecompressedSize))
        }

        let decompressedData = Data(decompressedBuffer.prefix(Int(actualDecompressedSize)))
        let duration = ProcessInfo.processInfo.systemUptime - startTime
        Logger.current
            .debug(
                "DataCompressingService decompressed data from \(data.count) to \(decompressedData.count) bytes in \(String(format: "%.3f", duration))s"
            )

        return decompressedData
    }
}

enum DataCompressionError: Error, LocalizedError {
    case compressionFailed(errorCode: Int)
    case decompressionFailed(errorCode: Int)
    case cannotDetermineDecompressedSize

    var errorDescription: String? {
        switch self {
        case let .compressionFailed(errorCode):
            return "Compression failed with error code: \(errorCode)"
        case let .decompressionFailed(errorCode):
            return "Decompression failed with error code: \(errorCode)"
        case .cannotDetermineDecompressedSize:
            return "Cannot determine decompressed size"
        }
    }
}
