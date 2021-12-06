import Core
import Foundation
public protocol FeatureBContract {
    func run()
    func expose() -> CoreClass
}
