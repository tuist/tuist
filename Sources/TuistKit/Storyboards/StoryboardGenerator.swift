import Basic
import Foundation
import TuistCore

enum StoryboardGenerationError: FatalError, Equatable {
    case alreadyExisting(AbsolutePath)
    case launchScreenUnsupported(Platform)

    var description: String {
        switch self {
        case let .alreadyExisting(path):
            return "A storyboard already exists at path \(path.asString)"
        case let .launchScreenUnsupported(platform):
            return "\(platform) does not support a launch screen storyboard"
        }
    }

    var type: ErrorType {
        switch self {
        case .alreadyExisting: return .abort
        case .launchScreenUnsupported: return .abort
        }
    }

    static func == (lhs: StoryboardGenerationError, rhs: StoryboardGenerationError) -> Bool {
        switch (lhs, rhs) {
        case let (.alreadyExisting(lhsPath), .alreadyExisting(rhsPath)):
            return lhsPath == rhsPath
        case let (.launchScreenUnsupported(lhsPlatform), .launchScreenUnsupported(rhsPlatform)):
            return lhsPlatform == rhsPlatform
        default:
            return false
        }
    }
}

protocol StoryboardGenerating: AnyObject {
    func generate(path: AbsolutePath,
                  name: String,
                  platform: Platform,
                  isLaunchScreen: Bool) throws
}

final class StoryboardGenerator: StoryboardGenerating {
    // MARK: - Attributes

    private let fileHandler: FileHandling

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    func generate(path: AbsolutePath, name: String, platform: Platform, isLaunchScreen: Bool) throws {
        if isLaunchScreen, !platform.supportsLaunchScreen {
            throw StoryboardGenerationError.launchScreenUnsupported(platform)
        }

        let storyboardPath = path.appending(component: "\(name).storyboard")

        if fileHandler.exists(storyboardPath) {
            throw StoryboardGenerationError.alreadyExisting(storyboardPath)
        }

        try StoryboardGenerator.xcstoarybaordContent(platform: platform, isLaunchScreen: isLaunchScreen)
            .write(to: storyboardPath.url,
                   atomically: true,
                   encoding: .utf8)
    }

    static func xcstoarybaordContent(platform _: Platform, isLaunchScreen: Bool) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="14460.31" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="\(isLaunchScreen ? "YES" : "NO")" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
        <device id="retina4_7" orientation="portrait">
        <adaptation id="fullscreen"/>
        </device>
        <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="14460.20"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
        </dependencies>
        <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
        <objects>
        <viewController id="01J-lp-oVM" sceneMemberID="viewController">
        <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
        <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
        <viewLayoutGuide key="safeArea" id="Bcu-3y-fUS"/>
        </view>
        </viewController>
        <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
        </objects>
        <point key="canvasLocation" x="53" y="375"/>
        </scene>
        </scenes>
        </document>
        """
    }
}
