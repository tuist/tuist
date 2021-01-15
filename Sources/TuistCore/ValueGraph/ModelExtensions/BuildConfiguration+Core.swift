import Foundation
import TuistSupport
import TuistGraph

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { name }
}
