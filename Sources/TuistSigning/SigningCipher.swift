import Basic
import Crypto
import TuistSupport
import TuistLoader

public protocol SigningCiphering {
    func encryptSigning(at path: AbsolutePath) throws
    func decryptSigning(at path: AbsolutePath) throws
}

public final class SigningCipher: SigningCiphering {
    public init() { }
    
    public func encryptSigning(at path: AbsolutePath) throws {
        let (signingKeyFiles, masterKey) = try signingData(at: path)
        let cipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map {
                try AES.GCM.seal($0, using: masterKey)
            }
        
        try zip(cipheredKeys, signingKeyFiles).forEach {
            guard let combinedData = $0.combined else {
                Printer.shared.print(warning: "Could not encode file at: \($1.pathString)")
                return
            }
            try combinedData.write(to: $1.url)
        }
    }
    
    public func decryptSigning(at path: AbsolutePath) throws {
        let (signingKeyFiles, masterKey) = try signingData(at: path)
        let decipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map(AES.GCM.SealedBox.init)
            .map {
                try AES.GCM.open($0, using: masterKey)
            }
        
        try zip(decipheredKeys, signingKeyFiles).forEach {
            try $0.write(to: $1.url)
        }
    }
    
    // MARK: - Helpers
    
    private func signingData(at path: AbsolutePath) throws -> (signingKeyFiles: [AbsolutePath], masterKey: SymmetricKey) {
        guard let rootDirectory = RootDirectoryLocator.shared.locate(from: path) else { fatalError() }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        let masterKey = try self.masterKey(from: signingDirectory)
        let signingKeyFiles = FileHandler.shared.glob(signingDirectory, glob: "**/*")
            .filter { $0.pathString != signingDirectory.appending(component: "master.key").pathString }
            .filter { !FileHandler.shared.isFolder($0) }
        return (signingKeyFiles: signingKeyFiles, masterKey: masterKey)
    }
    
    private func masterKey(from signingDirectory: AbsolutePath) throws -> SymmetricKey {
        let plainMasterKey = try FileHandler.shared.readTextFile(signingDirectory.appending(component: "master.key"))
        return SymmetricKey(data: SHA256(plainMasterKey).digest())
    }
}
