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

    var type: ErrorType {
        switch self {
        case .failedToEncrypt, .failedToDecrypt, .ivGenerationFailed,
             .masterKeyNotFound, .signingDirectoryNotFound:
            return .abort
        }
    }

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
    /// - Parameters:
    ///     - keepFiles: Keep unencrypted files
    func encryptSigning(at path: AbsolutePath, keepFiles: Bool) throws
    /// Decrypts all signing files at `Tuist/Signing
    /// - Parameters:
    ///     - keepFiles: Keep encrypted files
    func decryptSigning(at path: AbsolutePath, keepFiles: Bool) throws
}

public extension SigningCiphering {
    func encryptSigning(at path: AbsolutePath) throws {
        try encryptSigning(at: path, keepFiles: false)
    }

    func decryptSigning(at path: AbsolutePath) throws {
        try decryptSigning(at: path, keepFiles: false)
    }
}

public final class SigningCipher: SigningCiphering {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let signingFilesLocator: SigningFilesLocating

    /// Public initializer
    public convenience init() {
        self.init(rootDirectoryLocator: RootDirectoryLocator(),
                  signingFilesLocator: SigningFilesLocator())
    }

    init(rootDirectoryLocator: RootDirectoryLocating,
         signingFilesLocator: SigningFilesLocating) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.signingFilesLocator = signingFilesLocator
    }

    public func encryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        let masterKey = try self.masterKey(at: path)
        let signingKeyFiles = try signingFilesLocator.locateUnencryptedSigningFiles(at: path)
        guard !signingKeyFiles.isEmpty else { return }
        let cipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map { try encryptData($0, masterKey: masterKey) }

        let correctlyEncryptedSigningFiles = try self.correctlyEncryptedSigningFiles(at: path, masterKey: masterKey)

        try signingFilesLocator.locateEncryptedSigningFiles(at: path)
            .filter { !correctlyEncryptedSigningFiles.contains($0) }
            .forEach(FileHandler.shared.delete)

        try zip(cipheredKeys, signingKeyFiles)
            .filter { _, file in !correctlyEncryptedSigningFiles.contains(file) }
            .forEach { key, file in
                logger.debug("Encrypting \(file.pathString)")
                let encryptedPath = AbsolutePath(file.pathString + "." + Constants.encryptedExtension)
                try key.write(to: encryptedPath.url)
            }

        if !keepFiles {
            try signingKeyFiles.forEach(FileHandler.shared.delete)
        }
    }

    public func decryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        let masterKey = try self.masterKey(at: path)
        let signingKeyFiles = try signingFilesLocator.locateEncryptedSigningFiles(at: path)
        guard !signingKeyFiles.isEmpty else { return }
        let decipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map {
                try decryptData($0, masterKey: masterKey)
            }

        try signingFilesLocator.locateUnencryptedSigningFiles(at: path)
            .forEach(FileHandler.shared.delete)

        try zip(decipheredKeys, signingKeyFiles).forEach {
            logger.debug("Decrypting \($1.pathString)")
            let decryptedPath = AbsolutePath($1.parentDirectory.pathString + "/" + $1.basenameWithoutExt)
            try $0.write(to: decryptedPath.url)
        }

        if !keepFiles {
            try signingKeyFiles.forEach(FileHandler.shared.delete)
        }
    }

    // MARK: - Helpers

    /// - Returns: Array of files that do need to be reencrypted
    private func correctlyEncryptedSigningFiles(at path: AbsolutePath, masterKey: Data) throws -> [AbsolutePath] {
        try signingFilesLocator.locateUnencryptedSigningFiles(at: path).filter { unencryptedFile in
            let encryptedFile = AbsolutePath(unencryptedFile.pathString + "." + Constants.encryptedExtension)
            guard FileHandler.shared.exists(encryptedFile) else { return false }
            return try isEncryptionNeeded(encryptedFile: encryptedFile, unencryptedFile: unencryptedFile, masterKey: masterKey)
        }
    }

    /// Determines if encryption is needed
    private func isEncryptionNeeded(encryptedFile: AbsolutePath, unencryptedFile: AbsolutePath, masterKey: Data) throws -> Bool {
        guard
            let encodedString = String(data: try FileHandler.shared.readFile(encryptedFile), encoding: .utf8),
            let dividerIndex = encodedString.firstIndex(of: "-"),
            let iv = Data(base64Encoded: String(encodedString.prefix(upTo: dividerIndex)))
        else { throw SigningCipherError.failedToDecrypt("corrupted data") }

        let aesCipher = try AES(key: masterKey.bytes, blockMode: CTR(iv: iv.bytes), padding: .noPadding)
        let unencryptedData = try FileHandler.shared.readFile(unencryptedFile)
        guard
            let encryptedBase64String = try aesCipher.encrypt(unencryptedData.bytes).toBase64(),
            let data = (iv.base64EncodedString() + "-" + encryptedBase64String).data(using: .utf8)
        else { throw SigningCipherError.failedToEncrypt }

        return try FileHandler.shared.readFile(encryptedFile) == data
    }

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

    /// - Returns: Master key data
    private func masterKey(at path: AbsolutePath) throws -> Data {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningCipherError.signingDirectoryNotFound(path) }
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
