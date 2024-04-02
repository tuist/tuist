**EXTENSION**

# `SettingsDictionary`
```swift
extension SettingsDictionary
```

## Methods
### `merge(_:)`

```swift
public mutating func merge(_ other: SettingsDictionary)
```

### `merging(_:)`

```swift
public func merging(_ other: SettingsDictionary) -> SettingsDictionary
```

### `manualCodeSigning(identity:provisioningProfileSpecifier:)`

```swift
public func manualCodeSigning(identity: String? = nil, provisioningProfileSpecifier: String? = nil) -> SettingsDictionary
```

Sets `"CODE_SIGN_STYLE"` to `"Manual"`,` "CODE_SIGN_IDENTITY"` to `identity`, and `"PROVISIONING_PROFILE_SPECIFIER"` to
`provisioningProfileSpecifier`

### `automaticCodeSigning(devTeam:)`

```swift
public func automaticCodeSigning(devTeam: String) -> SettingsDictionary
```

Sets `"CODE_SIGN_STYLE"` to `"Automatic"` and `"DEVELOPMENT_TEAM"` to `devTeam`

### `codeSignIdentityAppleDevelopment()`

```swift
public func codeSignIdentityAppleDevelopment() -> SettingsDictionary
```

Sets `"CODE_SIGN_IDENTITY"` to `"Apple Development"`

### `codeSignIdentity(_:)`

```swift
public func codeSignIdentity(_ identity: String) -> SettingsDictionary
```

Sets `"CODE_SIGN_IDENTITY"` to `identity`

### `currentProjectVersion(_:)`

```swift
public func currentProjectVersion(_ version: String) -> SettingsDictionary
```

Sets `"CURRENT_PROJECT_VERSION"` to `version`

### `marketingVersion(_:)`

```swift
public func marketingVersion(_ version: String) -> SettingsDictionary
```

Sets `"MARKETING_VERSION"` to `version`

### `appleGenericVersioningSystem()`

```swift
public func appleGenericVersioningSystem() -> SettingsDictionary
```

Sets `"VERSIONING_SYSTEM"` to `"apple-generic"`

### `versionInfo(_:prefix:suffix:)`

```swift
public func versionInfo(_ version: String, prefix: String? = nil, suffix: String? = nil) -> SettingsDictionary
```

Sets "VERSION_INFO_STRING" to `version`. If `prefix` and `suffix` are not `nil`, they're used as `"VERSION_INFO_PREFIX"`
and `"VERSION_INFO_SUFFIX"` respectively.

### `swiftVersion(_:)`

```swift
public func swiftVersion(_ version: String) -> SettingsDictionary
```

Sets `"SWIFT_VERSION"` to `version`

### `otherSwiftFlags(_:)`

```swift
public func otherSwiftFlags(_ flags: String...) -> SettingsDictionary
```

Sets `"OTHER_SWIFT_FLAGS"` to `flags`

### `otherSwiftFlags(_:)`

```swift
public func otherSwiftFlags(_ flags: [String]) -> SettingsDictionary
```

Sets `"OTHER_SWIFT_FLAGS"` to `flags`

### `swiftActiveCompilationConditions(_:)`

```swift
public func swiftActiveCompilationConditions(_ conditions: String...) -> SettingsDictionary
```

Sets `"SWIFT_ACTIVE_COMPILATION_CONDITIONS"` to `conditions`

### `swiftActiveCompilationConditions(_:)`

```swift
public func swiftActiveCompilationConditions(_ conditions: [String]) -> SettingsDictionary
```

Sets `"SWIFT_ACTIVE_COMPILATION_CONDITIONS"` to `conditions`

### `swiftCompilationMode(_:)`

```swift
public func swiftCompilationMode(_ mode: SwiftCompilationMode) -> SettingsDictionary
```

Sets `"SWIFT_COMPILATION_MODE"` to the available `SwiftCompilationMode` (`"singlefile"` or `"wholemodule"`)

### `swiftOptimizationLevel(_:)`

```swift
public func swiftOptimizationLevel(_ level: SwiftOptimizationLevel) -> SettingsDictionary
```

Sets `"SWIFT_OPTIMIZATION_LEVEL"` to the available `SwiftOptimizationLevel` (`"-O"`, `"-Onone"` or `"-Osize"`)

### `swiftOptimizeObjectLifetimes(_:)`

```swift
public func swiftOptimizeObjectLifetimes(_ enabled: Bool) -> SettingsDictionary
```

Sets `"SWIFT_OPTIMIZE_OBJECT_LIFETIME"` to `"YES"` or `"NO"`

### `swiftObjcBridgingHeaderPath(_:)`

```swift
public func swiftObjcBridgingHeaderPath(_ path: String) -> SettingsDictionary
```

Sets `"SWIFT_OBJC_BRIDGING_HEADER"` to `path`

### `otherCFlags(_:)`

```swift
public func otherCFlags(_ flags: [String]) -> SettingsDictionary
```

Sets `"OTHER_CFLAGS"` to `flags`

### `otherLinkerFlags(_:)`

```swift
public func otherLinkerFlags(_ flags: [String]) -> SettingsDictionary
```

Sets `"OTHER_LDFLAGS"` to `flags`

### `bitcodeEnabled(_:)`

```swift
public func bitcodeEnabled(_ enabled: Bool) -> SettingsDictionary
```

Sets `"ENABLE_BITCODE"` to `"YES"` or `"NO"`

### `debugInformationFormat(_:)`

```swift
public func debugInformationFormat(_ format: DebugInformationFormat) -> SettingsDictionary
```

Sets `"DEBUG_INFORMATION_FORMAT"`to `"dwarf"` or `"dwarf-with-dsym"`
