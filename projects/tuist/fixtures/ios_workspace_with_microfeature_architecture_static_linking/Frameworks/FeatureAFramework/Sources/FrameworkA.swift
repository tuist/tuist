import Foundation
import FeatureContracts

class FrameworkA {
	func run(featureB: FeatureBContract) {
		featureB.run()
        let a = featureB.expose()
        print(a)
	}
}
