**ENUM**

# `ScreenCaptureFormat`

```swift
public enum ScreenCaptureFormat: String, Codable
```

Preferred screen capture format for UI tests results in Xcode 15+

Available options are screen recordings and screenshots.

In Xcode 15 screen recordings are enabled by default (in favour of screenshots).
This setting is ignored by Xcode 14.x and prior.

## Cases
### `screenshots`

```swift
case screenshots
```

Screenshots

### `screenRecording`

```swift
case screenRecording
```

Automatic screen recordings
