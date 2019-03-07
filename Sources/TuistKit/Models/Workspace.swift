import Basic
import Foundation
import TuistCore

class Workspace: Equatable {
    // MARK: - Attributes
    
    public indirect enum Element: Equatable {
        case file(path: AbsolutePath)
        case group(name: String, contents: [Element])
        case project(path: AbsolutePath)
    }
        
    let name: String
    let elements: [Element]

    // MARK: - Init

    init(name: String, elements: [Element]) {
        self.name = name
        self.elements = elements
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.name == rhs.name && lhs.elements == rhs.elements
    }
}
