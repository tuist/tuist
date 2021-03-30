import Foundation
import Core
public protocol FeatureBContract {
    func run()
    func expose() -> CoreClass
}
