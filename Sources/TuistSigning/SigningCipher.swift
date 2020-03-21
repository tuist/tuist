import Basic
import CryptoSwift
import Foundation
import TuistCore
import TuistSupport

enum SigningCipherError: FatalError, Equatable {
    case failedToEncrypt
    case masterKeyNotFound(AbsolutePath)
    case rootDirectoryNotFound(AbsolutePath)

    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case .failedToEncrypt:
            return "Encryption failed"
        case let .masterKeyNotFound(masterKeyPath):
            return "Could not find master.key at \(masterKeyPath.pathString)"
        case let .rootDirectoryNotFound(fromPath):
            return "Could not find root directory from \(fromPath.pathString)"
        }
    }
}

public protocol SigningCiphering {
    func encryptSigning(at path: AbsolutePath) throws
    func decryptSigning(at path: AbsolutePath) throws
}

public final class SigningCipher: SigningCiphering {
    public init() {}

    public func encryptSigning(at path: AbsolutePath) throws {
        let (signingKeyFiles, masterKey) = try signingData(at: path)
        let cipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map { try encryptData($0, masterKey: masterKey) }

        try zip(cipheredKeys, signingKeyFiles).forEach {
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
        else { throw SigningCipherError.failedToEncrypt }

        let dataToDecrypt = Data(base64Encoded: String(encodedString.suffix(from: dividerIndex).dropFirst()))
        let aesCipher = try AES(key: masterKey.bytes, blockMode: CTR(iv: iv.bytes), padding: .noPadding)
        guard let decryptedData = try dataToDecrypt?.decrypt(cipher: aesCipher) else { throw SigningCipherError.failedToEncrypt }
        return decryptedData
    }

    /// - Returns: Files we want encrypt/decrypt along with master key data
    private func signingData(at path: AbsolutePath) throws -> (signingKeyFiles: [AbsolutePath], masterKey: Data) {
        guard
            let rootDirectory = RootDirectoryLocator.shared.locate(from: path)
        else { throw SigningCipherError.rootDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        let masterKey = try self.masterKey(from: signingDirectory)
        // Find all files in `signingDirectory` with the exception of "master.key"
        let signingKeyFiles = FileHandler.shared.glob(signingDirectory, glob: "**/*")
            .filter { $0.pathString != signingDirectory.appending(component: "master.key").pathString }
            .filter { !FileHandler.shared.isFolder($0) }
        return (signingKeyFiles: signingKeyFiles, masterKey: masterKey)
    }

    /// - Returns: Master key data
    private func masterKey(from signingDirectory: AbsolutePath) throws -> Data {
        let masterKeyFile = signingDirectory.appending(component: "master.key")
        guard FileHandler.shared.exists(masterKeyFile) else { throw SigningCipherError.masterKeyNotFound(masterKeyFile) }
        let plainMasterKey = try FileHandler.shared.readFile(masterKeyFile)
        return plainMasterKey.sha256()
    }

    /// - Returns: Data of generated initialization vector
    private func generateIv() throws -> Data {
        let blockSize = 16
        var iv = Data(repeating: 0, count: blockSize)
        let result = iv.withUnsafeMutableBytes { bytes -> Int32 in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            return SecRandomCopyBytes(kSecRandomDefault, blockSize, baseAddress)
        }
        guard result == errSecSuccess else { throw SigningCipherError.failedToEncrypt }
        return iv
    }
}
