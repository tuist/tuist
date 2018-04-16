import Foundation

protocol XcodeRepresentable {
    associatedtype E
    var xcodeValue: E { get }
}
