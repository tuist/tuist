import Core
import Foundation

public enum Report {
    public static func render(_ ledger: Ledger) -> String {
        let lines = ledger.entries
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
        return (lines + ["total: \(ledger.total)", "checksum: \(ledger.checksum.hex)", "salt: \(salt)"])
            .joined(separator: "\n")
    }
}
