import SwiftSyntax

public func identifierText(_ name: String) -> String {
    TokenSyntax.identifier(name).text
}
