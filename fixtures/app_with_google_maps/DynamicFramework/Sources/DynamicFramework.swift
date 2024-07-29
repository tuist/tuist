import Foundation
import GoogleMaps
import UIKit

public class Mapper: UIView {
    public static func provide(key: String) {
        GMSServices.provideAPIKey(key)
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        let mapView = GMSMapView()
        mapView.delegate = self
        addSubview(mapView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension Mapper: GMSMapViewDelegate {
    public func mapView(_: GMSMapView, didChange _: GMSCameraPosition) {}
}
