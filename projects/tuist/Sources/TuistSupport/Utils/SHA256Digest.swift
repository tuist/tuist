//
//  SHA256Digest.swift
//  TuistSupport
//
//  Created by Maksym Prokopchuk on 23.11.19.
//

import CommonCrypto
import Foundation

// https://inneka.com/programming/swift/sha256-in-swift/

final class SHA256Digest {
    enum InputStreamError: Error {
        case createFailed(URL)
        case readFailed
    }

    private lazy var context: CC_SHA256_CTX = {
        var shaContext = CC_SHA256_CTX()
        CC_SHA256_Init(&shaContext)
        return shaContext
    }()

    init() {}

    static func file(at url: URL) throws -> Data {
        let sha256 = SHA256Digest()
        try sha256.update(url: url)
        return sha256.finalize()
    }

    private func update(url: URL) throws {
        guard let inputStream = InputStream(url: url) else {
            throw InputStreamError.createFailed(url)
        }
        return try update(inputStream: inputStream)
    }

    private func update(inputStream: InputStream) throws {
        inputStream.open()
        defer { inputStream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                // Stream error occured
                throw (inputStream.streamError ?? InputStreamError.readFailed)
            } else if bytesRead == 0 {
                // EOF
                break
            }
            update(bytes: buffer, length: bytesRead)
        }
    }

    private func update(bytes: UnsafeRawPointer?, length: Int) {
        _ = CC_SHA256_Update(&context, bytes, CC_LONG(length))
    }

    private func finalize() -> Data {
        var resultBuffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&resultBuffer, &context)
        return Data(resultBuffer)
    }
}
