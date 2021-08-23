import Foundation

public enum MacArchitecture: String, Codable {
    case x8664 = "x86_64"
    case arm64
    
    public var homebrewPath: String {
        switch self {
        case .arm64:
            return "/opt/homebrew"
        case .x8664:
            return "/usr/bin/env"
        }
    }
    
    public var homebrewArch: String {
        return "-\(self.rawValue)"
    }
}
