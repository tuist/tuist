import Foundation
import libzstd

enum REAPICompression {
    static let threshold = 1024

    static func compress(_ data: Data) throws -> Data {
        var output = Data(count: ZSTD_compressBound(data.count))
        let count = output.count
        let size = data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                ZSTD_compress(destination.baseAddress, count, source.baseAddress, data.count, 1)
            }
        }
        try check(size)
        output.count = size
        return output
    }

    static func decompress(_ data: Data, size: Int64) throws -> Data {
        let decoder = try Decoder(size: size)
        var result = Data()
        try decoder.decode(data) { result.append($0) }
        try decoder.finish()
        return result
    }

    private static func check(_ result: Int) throws {
        guard ZSTD_isError(result) == 0 else { throw REAPICacheError.corruptBlob }
    }

    final class Encoder {
        private let context: OpaquePointer

        init() throws {
            guard let context = ZSTD_createCStream() else { throw REAPICacheError.corruptBlob }
            self.context = context
            try check(ZSTD_initCStream(context, 1))
        }

        deinit { ZSTD_freeCStream(context) }

        func encode(_ data: Data, finish: Bool) throws -> Data {
            var result = Data()
            try data.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: data.count, pos: 0)
                var buffer = [UInt8](repeating: 0, count: ZSTD_CStreamOutSize())
                var remaining = 1
                repeat {
                    try buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        remaining = ZSTD_compressStream2(context, &output, &input, finish ? ZSTD_e_end : ZSTD_e_continue)
                        try check(remaining)
                        result.append(contentsOf: destination.prefix(output.pos))
                    }
                } while input.pos < input.size || (finish && remaining != 0)
            }
            return result
        }
    }

    final class Decoder {
        private let context: OpaquePointer
        private var remaining: Int64
        private var frameRemaining = 1

        init(size: Int64) throws {
            guard size >= 0, let context = ZSTD_createDStream() else { throw REAPICacheError.corruptBlob }
            self.context = context
            remaining = size
            try check(ZSTD_initDStream(context))
            // Bound the decoding window independently of the server's frame header.
            try check(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, 27))
        }

        deinit { ZSTD_freeDStream(context) }

        func decode(_ data: Data, consume: (Data) throws -> Void) throws {
            try data.withUnsafeBytes { source in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: data.count, pos: 0)
                var buffer = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
                var full = false
                repeat {
                    try buffer.withUnsafeMutableBytes { destination in
                        var output = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        frameRemaining = ZSTD_decompressStream(context, &output, &input)
                        try check(frameRemaining)
                        guard Int64(output.pos) <= remaining else { throw REAPICacheError.corruptBlob }
                        remaining -= Int64(output.pos)
                        full = output.pos == output.size
                        if output.pos > 0 { try consume(Data(destination.prefix(output.pos))) }
                    }
                } while input.pos < input.size || (full && frameRemaining != 0)
            }
        }

        func finish() throws {
            guard remaining == 0, frameRemaining == 0 else { throw REAPICacheError.corruptBlob }
        }
    }
}
