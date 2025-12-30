import Foundation
import GoogleMaps
import UIKit

public class Mapper: UIView {
    public static func provide(key: String) {
        GMSServices.provideAPIKey(key)
    }

    public let mapView: GMSMapView!

    override public init(frame: CGRect) {
        mapView = GMSMapView()

        super.init(frame: frame)

        addSubview(mapView)
        mapView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension Mapper: GMSMapViewDelegate {
    public func mapView(_: GMSMapView, didChange _: GMSCameraPosition) {}
}
