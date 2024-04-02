**STRUCT**

# `SchemeDiagnosticsOptions`

```swift
public struct SchemeDiagnosticsOptions: Equatable, Codable
```

Options to configure scheme diagnostics for run and test actions.

## Properties
### `addressSanitizerEnabled`

```swift
public var addressSanitizerEnabled: Bool
```

Enable the address sanitizer

### `detectStackUseAfterReturnEnabled`

```swift
public var detectStackUseAfterReturnEnabled: Bool
```

Enable the detect use of stack after return of address sanitizer

### `threadSanitizerEnabled`

```swift
public var threadSanitizerEnabled: Bool
```

Enable the thread sanitizer

### `mainThreadCheckerEnabled`

```swift
public var mainThreadCheckerEnabled: Bool
```

Enable the main thread cheker

### `performanceAntipatternCheckerEnabled`

```swift
public var performanceAntipatternCheckerEnabled: Bool
```

Enable thread performance checker

## Methods
### `options(addressSanitizerEnabled:detectStackUseAfterReturnEnabled:threadSanitizerEnabled:mainThreadCheckerEnabled:performanceAntipatternCheckerEnabled:)`

```swift
public static func options(
    addressSanitizerEnabled: Bool = false,
    detectStackUseAfterReturnEnabled: Bool = false,
    threadSanitizerEnabled: Bool = false,
    mainThreadCheckerEnabled: Bool = true,
    performanceAntipatternCheckerEnabled: Bool = true
) -> SchemeDiagnosticsOptions
```
