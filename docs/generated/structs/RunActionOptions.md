**STRUCT**

# `RunActionOptions`

```swift
public struct RunActionOptions: Equatable, Codable
```

Options for the `RunAction` action

## Properties
### `language`

```swift
public var language: SchemeLanguage?
```

Language to use when running the app.

### `region`

```swift
public var region: String?
```

Region to use when running the app.

### `storeKitConfigurationPath`

```swift
public var storeKitConfigurationPath: Path?
```

The path of the
[StoreKit configuration
file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).

### `simulatedLocation`

```swift
public var simulatedLocation: SimulatedLocation?
```

A simulated GPS location to use when running the app.

### `enableGPUFrameCaptureMode`

```swift
public var enableGPUFrameCaptureMode: GPUFrameCaptureMode
```

Configure your project to work with the Metal frame debugger.

## Methods
### `options(language:region:storeKitConfigurationPath:simulatedLocation:enableGPUFrameCaptureMode:)`

```swift
public static func options(
    language: SchemeLanguage? = nil,
    region: String? = nil,
    storeKitConfigurationPath: Path? = nil,
    simulatedLocation: SimulatedLocation? = nil,
    enableGPUFrameCaptureMode: GPUFrameCaptureMode = GPUFrameCaptureMode.default
) -> Self
```

Creates an `RunActionOptions` instance

- Parameters:
    - language: language (e.g. "en").

    - region: region (e.g. "US").

    - storeKitConfigurationPath: The path of the
    [StoreKit configuration
file](https://developer.apple.com/documentation/xcode/setting_up_storekit_testing_in_xcode#3625700).
    Please note that this file is automatically added to the Project/Workpace. You should not add it manually.
    The default value is `nil`, which results in no configuration defined for the scheme

    - simulatedLocation: The simulated GPS location to use when running the app.
    Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project's resources.

    - enableGPUFrameCaptureMode: The Metal Frame Capture mode to use. e.g: .disabled
    If your target links to the Metal framework, Xcode enables GPU Frame Capture.
    You can disable it to test your app in best perfomance.

#### Parameters

| Name | Description |
| ---- | ----------- |
| language | language (e.g. “en”). |
| region | region (e.g. “US”). |
| storeKitConfigurationPath | The path of the . Please note that this file is automatically added to the Project/Workpace. You should not add it manually. The default value is `nil`, which results in no configuration defined for the scheme |
| simulatedLocation | The simulated GPS location to use when running the app. Please note that the `.custom(gpxPath:)` case must refer to a valid GPX file in your project’s resources. |
| enableGPUFrameCaptureMode | The Metal Frame Capture mode to use. e.g: .disabled If your target links to the Metal framework, Xcode enables GPU Frame Capture. You can disable it to test your app in best perfomance. |