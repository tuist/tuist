import Foundation
import TuistCore

struct Graph: Codable, Equatable {
    let iOSDependencies: [String]
    let tvOSDependencies: [String]
    let macOSDependencies: [String]
    let watchOSDependencies: [String]
    
    static var empty: Self {
        .init(iOSDependencies: [], tvOSDependencies: [], macOSDependencies: [], watchOSDependencies: [])
    }
    
    // MARK: - Helpers
    
    func dependencies(for platform: Platform) -> [String] {
        switch platform {
        case .iOS: return iOSDependencies
        case .tvOS: return tvOSDependencies
        case .macOS: return macOSDependencies
        case .watchOS: return watchOSDependencies
        }
    }
    
    func updatingDependencies(_ dependencies: [String], for platform: Platform) -> Self {
        .init(
            iOSDependencies: platform == .iOS ? dependencies : iOSDependencies,
            tvOSDependencies: platform == .tvOS ? dependencies : tvOSDependencies,
            macOSDependencies: platform == .macOS ? dependencies : macOSDependencies,
            watchOSDependencies: platform == .watchOS ? dependencies : watchOSDependencies
        )
    }
}
