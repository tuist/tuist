import Basic
import Crypto
import TuistSupport
import TuistLoader

public protocol SigningCiphering {
    func encryptSigning(at path: AbsolutePath) throws
}

public final class SigningCipher: SigningCiphering {
    public init() { }
    
    public func encryptSigning(at path: AbsolutePath) throws {
        guard let rootDirectory = RootDirectoryLocator.shared.locate(from: path) else { fatalError() }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        let masterKey = SymmetricKey(data: try FileHandler.shared.readFile(signingDirectory.appending(component: "master.key")))
        let signingKeyFiles = FileHandler.shared.glob(signingDirectory, glob: "**/*")
            .filter { $0.pathString != signingDirectory.appending(component: "master.key").pathString }
            .filter { !FileHandler.shared.isFolder($0) }
        let cipheredKeys = try signingKeyFiles
            .map(FileHandler.shared.readFile)
            .map {
                try AES.GCM.seal($0, using: masterKey)
            }
            .map(\.ciphertext)
        
        try zip(cipheredKeys, signingKeyFiles).forEach {
            try $0.write(to: $1.url)
        }
    }
}
