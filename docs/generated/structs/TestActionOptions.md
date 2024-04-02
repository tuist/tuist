**STRUCT**

# `TestActionOptions`

```swift
public struct TestActionOptions: Equatable, Codable
```

The type `TestActionOptions` represents a set of options for a test action.

## Properties
### `language`

```swift
public var language: SchemeLanguage?
```

Language used to run the tests.

### `region`

```swift
public var region: String?
```

Region used to run the tests.

### `preferredScreenCaptureFormat`

```swift
public var preferredScreenCaptureFormat: ScreenCaptureFormat?
```

Preferred screen capture format for UI tests results in Xcode 15+

### `coverage`

```swift
public var coverage: Bool
```

Whether the scheme should or not gather the test coverage data.

### `codeCoverageTargets`

```swift
public var codeCoverageTargets: [TargetReference]
```

A list of targets you want to gather the test coverage data for them, which are defined in the project.

## Methods
### `options(language:region:preferredScreenCaptureFormat:coverage:codeCoverageTargets:)`

```swift
public static func options(
    language: SchemeLanguage? = nil,
    region: String? = nil,
    preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
    coverage: Bool = false,
    codeCoverageTargets: [TargetReference] = []
) -> TestActionOptions
```

Returns a set of options for a test action.
- Parameters:
  - language: Language used for running the tests.
  - region: Region used for running the tests.
  - coverage: Whether test coverage should be collected.
  - codeCoverageTargets: List of test targets whose code coverage information should be collected.
- Returns: A set of options.

#### Parameters

| Name | Description |
| ---- | ----------- |
| language | Language used for running the tests. |
| region | Region used for running the tests. |
| coverage | Whether test coverage should be collected. |
| codeCoverageTargets | List of test targets whose code coverage information should be collected. |