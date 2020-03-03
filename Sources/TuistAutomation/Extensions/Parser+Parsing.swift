import Foundation
import XcbeautifyLib

protocol Parsing {
    func parse(line: String, colored: Bool) -> String?
}

extension Parser: Parsing {}
