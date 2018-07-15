import Foundation

protocol Installing: AnyObject {
    func install(reference: String) throws
}

final class Installer: Installing {
    func install(reference _: String) throws {
    }
}
