import Basic
import CryptoSwift
import Foundation
import TuistCore
import TuistSupport

enum SigningCipherError: FatalError, Equatable {
    case failedToEncrypt
    case failedToDecrypt(String)
    case ivGenerationFailed(String)
    case masterKeyNotFound(AbsolutePath)
    case signingDirectoryNotFound(AbsolutePath)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case .failedToEncrypt:
            return "Unable to encrypt data"
        case let .failedToDecrypt(reason):
            return "Could not decrypt data: \(reason)"
        case let .ivGenerationFailed(reason):
            return "Generation of IV failed with error: \(reason)"
        case let .masterKeyNotFound(masterKeyPath):
            return "Could not find master.key at \(masterKeyPath.pathString)"
        case let .signingDirectoryNotFound(fromPath):
            return "Could not find signing directory from \(fromPath.pathString)"
        }
    }
}

/// SigningCiphering handles all encryption/decryption of files needed for signing (certificates, profiles, etc.)
public protocol SigningCiphering {
    /// Encrypts all signing files at `Tuist/Signing`
    func encryptSigning(at path: AbsolutePath) throws
    /// Decrypts all signing files at `Tuist/Signing`
    func decryptSigning(at path: AbsolutePath) throws
}

public final class SigningCipher: SigningCiphering {
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Public initializer
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func encryptSigning(at path: AbsolutePath) throws {
        let (signingKeyFiles, masterKey) = try signingData(at: path)
        let cipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map { try encryptData($0, masterKey: masterKey) }

        try zip(cipheredKeys, signingKeyFiles).forEach {
            logger.debug("Encrypting \($1.pathString)")
            try $0.write(to: $1.url)
        }
    }

    public func decryptSigning(at path: AbsolutePath) throws {
        let (signingKeyFiles, masterKey) = try signingData(at: path)
        let decipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map {
                try decryptData($0, masterKey: masterKey)
            }

        try zip(decipheredKeys, signingKeyFiles).forEach {
            logger.debug("Decrypting \($1.pathString)")
            try $0.write(to: $1.url)
        }
    }

    // MARK: - Helpers

    /// Encrypts `data`
    /// - Parameters:
    ///     - data: Data to encrypt
    ///     - masterKey: Master key data
    /// - Returns: Encrypted data
    private func encryptData(_ data: Data, masterKey: Data) throws -> Data {
        let iv = try generateIv()
        let aesCipher = try AES(key: masterKey.bytes, blockMode: CTR(iv: iv.bytes), padding: .noPadding)
        guard
            let encryptedBase64String = try aesCipher.encrypt(data.bytes).toBase64(),
            let data = (iv.base64EncodedString() + "-" + encryptedBase64String).data(using: .utf8)
        else { throw SigningCipherError.failedToEncrypt }
        return data
    }

    /// Decrypts `data`
    /// - Parameters:
    ///     - data: Data to decrypt
    ///     - masterKey: Master key data
    /// - Returns: Decrypted data
    private func decryptData(_ data: Data, masterKey: Data) throws -> Data {
        guard
            let encodedString = String(data: data, encoding: .utf8),
            let dividerIndex = encodedString.firstIndex(of: "-"),
            let iv = Data(base64Encoded: String(encodedString.prefix(upTo: dividerIndex)))
        else { throw SigningCipherError.failedToDecrypt("corrupted data") }

        let dataToDecrypt = Data(base64Encoded: String(encodedString.suffix(from: dividerIndex).dropFirst()))
        let aesCipher = try AES(key: masterKey.bytes, blockMode: CTR(iv: iv.bytes), padding: .noPadding)
        guard
            let decryptedData = try dataToDecrypt?.decrypt(cipher: aesCipher)
        else { throw SigningCipherError.failedToDecrypt("data is in wrong format") }
        return decryptedData
    }

    /// - Returns: Files we want encrypt/decrypt along with master key data
    private func signingData(at path: AbsolutePath) throws -> (signingKeyFiles: [AbsolutePath], masterKey: Data) {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningCipherError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        let masterKey = try self.masterKey(from: rootDirectory)
        // Find all files in `signingDirectory` with the exception of Constants.masterKey
        let signingKeyFiles = FileHandler.shared.glob(signingDirectory, glob: "*")
        return (signingKeyFiles: signingKeyFiles, masterKey: masterKey)
    }

    /// - Returns: Master key data
    private func masterKey(from rootDirectory: AbsolutePath) throws -> Data {
        let masterKeyFile = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.masterKey)
        guard FileHandler.shared.exists(masterKeyFile) else { throw SigningCipherError.masterKeyNotFound(masterKeyFile) }
        let plainMasterKey = try FileHandler.shared.readFile(masterKeyFile)
        return plainMasterKey.sha256()
    }

    /// - Returns: Data of generated initialization vector
    private func generateIv() throws -> Data {
        let blockSize = 16
        var iv = Data(repeating: 0, count: blockSize)
        let result = try iv.withUnsafeMutableBytes { bytes -> Int32 in
            guard
                let baseAddress = bytes.baseAddress
            else { throw SigningCipherError.ivGenerationFailed("Base address not found") }
            return SecRandomCopyBytes(kSecRandomDefault, blockSize, baseAddress)
        }
        if result == errSecSuccess {
            return iv
        } else {
            if let errorMessage = SecCopyErrorMessageString(result, nil) {
                throw SigningCipherError.ivGenerationFailed(String(errorMessage))
            } else {
                throw SigningCipherError.ivGenerationFailed("code: \(result)")
            }
        }
    }
}
