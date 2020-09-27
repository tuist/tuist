import ProjectDescription

public enum PackageProductType: Hashable {
    
    case staticLibrary
    case dynamicLibrary
    
}

public extension PackageProductType {
    
    init(from projectValue: ProjectDescription.PackageProductType) {
        switch projectValue {
        case .dynamicLibrary:
            self = .dynamicLibrary
        case .staticLibrary:
            self = .staticLibrary
        }
    }
    
}
