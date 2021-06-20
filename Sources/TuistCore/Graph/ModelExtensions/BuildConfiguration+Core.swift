import Foundation
import TuistGraph
import TuistSupport

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { name }
}
