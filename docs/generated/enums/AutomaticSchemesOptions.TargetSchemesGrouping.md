**ENUM**

# `AutomaticSchemesOptions.TargetSchemesGrouping`

**Contents**

- [Cases](#cases)
  - `singleScheme`
  - `byNameSuffix(build:test:run:)`
  - `notGrouped`

```swift
public enum TargetSchemesGrouping: Codable, Equatable
```

Allows you to define what targets will be enabled for code coverage data gathering.

## Cases
### `singleScheme`

```swift
case singleScheme
```

Generate a single scheme for each project.

### `byNameSuffix(build:test:run:)`

```swift
case byNameSuffix(build: Set<String>, test: Set<String>, run: Set<String>)
```

Group schemes according to the suffix of their names.

### `notGrouped`

```swift
case notGrouped
```

Generate a scheme for each target.
