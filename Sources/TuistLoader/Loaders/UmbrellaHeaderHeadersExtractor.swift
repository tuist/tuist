import Foundation
import TSCBasic
import TuistSupport

public enum UmbrellaHeaderHeadersExtractor {
    public static func headers(
        from path: AbsolutePath,
        for productName: String?
    ) throws -> [String] {
        let umbrellaContent = try FileHandler.shared.readTextFile(path)
        let lines = umbrellaContent.components(separatedBy: .newlines)
        let expectedPrefixes = [
            "#import \"",
            "#import <",
        ]

        return lines.compactMap { line in
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard let matchingPrefix = expectedPrefixes.first(where: { line.hasPrefix($0) }) else {
                return nil
            }
            // also we need drop comments and spaces before comments
            guard let stripedWithoutComments = stripped.components(separatedBy: "//")
                .first?
                .trimmingCharacters(in: .whitespaces)
            else {
                return nil
            }
            let headerReference = stripedWithoutComments.dropFirst(matchingPrefix.count).dropLast()
            let headerComponents = headerReference.components(separatedBy: "/")

            // <ProductName/Header.h>
            // "ProductName/Header.h"
            let isValidProductPrefixedHeader = headerComponents.count == 2 &&
                productName != nil &&
                headerComponents[0] == productName

            // "Header.h"
            let isValidSingleHeader = headerComponents.count == 1

            guard isValidProductPrefixedHeader || isValidSingleHeader else {
                return nil
            }

            return headerComponents.last
        }
    }
}
