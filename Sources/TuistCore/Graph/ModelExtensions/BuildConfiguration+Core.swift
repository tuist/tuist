import Foundation
import TuistSupport
import XcodeGraph

extension BuildConfiguration: XcodeRepresentable {
    public var xcodeValue: String { name }
}
