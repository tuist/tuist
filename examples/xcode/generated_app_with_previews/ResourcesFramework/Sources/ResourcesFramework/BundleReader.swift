import Foundation

public func readFileFromBundle() -> String {
    let path = Bundle.module.url(forResource: "file", withExtension: "txt")!
    return try! String(contentsOf: path)
}
