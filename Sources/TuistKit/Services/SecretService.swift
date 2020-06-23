import Foundation
import Signals
import TSCBasic
import TuistGenerator
import TuistSupport

final class SecretService {
    private let secureStringGenerator: SecureStringGenerating

    convenience init() {
        self.init(secureStringGenerator: SecureStringGenerator())
    }

    init(secureStringGenerator: SecureStringGenerating) {
        self.secureStringGenerator = secureStringGenerator
    }

    func run() throws {
        let secret = try secureStringGenerator.generate()
        logger.log(level: .info, "\(secret)")
    }
}
