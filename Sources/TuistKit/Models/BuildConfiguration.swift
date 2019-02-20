import Foundation

enum BuildConfiguration: String, CaseIterable {
    case debug
    case release
}

extension BuildConfiguration: XcodeRepresentable {
    var xcodeValue: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        }
    }
}

struct ConfigurationList: Sequence {
    
    typealias Element = Configuration
    typealias Iterator = IndexingIterator<[Configuration]>
    
    let configurations: [Configuration]
    init(_ configurations: [Configuration]) {
        self.configurations = configurations
    }
    
    func makeIterator() -> ConfigurationList.Iterator {
        return configurations.makeIterator()
    }
    
}
