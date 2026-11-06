// Each imported framework is its own explicit module build, so a cold build
// asks the cache for dozens of independent keys at once.
import AppKit
import AVFoundation
import Combine
import CoreData
import CoreImage
import CoreLocation
import MapKit
import LookupDependency
import Network
import SwiftUI
import WebKit

public struct LookupFixture {
    public var name: String
    public var dependencyValue: Int { LookupDependency.value }
    public init(name: String) { self.name = name }
}
