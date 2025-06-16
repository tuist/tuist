import FeatureContracts
import Foundation

class FrameworkA {
    func run(featureB: FeatureBContract) {
        featureB.run()
        let a = featureB.expose()
        print(a)
    }
}
