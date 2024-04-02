**STRUCT**

# `Cloud`

**Contents**

- [Properties](#properties)
  - `url`
  - `projectId`
  - `options`
- [Methods](#methods)
  - `cloud(projectId:url:options:)`

```swift
public struct Cloud: Codable, Equatable
```

A cloud configuration, used for remote caching.

## Properties
### `url`

```swift
public var url: String
```

The base URL that points to the Cloud server.

### `projectId`

```swift
public var projectId: String
```

The project unique identifier.

### `options`

```swift
public var options: [Option]
```

The configuration options.

## Methods
### `cloud(projectId:url:options:)`

```swift
public static func cloud(projectId: String, url: String = "https://cloud.tuist.io", options: [Option] = []) -> Cloud
```

Returns a generic cloud configuration.
- Parameters:
  - projectId: Project unique identifier.
  - url: Base URL to the Cloud server.
  - options: Cloud options.
- Returns: A Cloud instance.

#### Parameters

| Name | Description |
| ---- | ----------- |
| projectId | Project unique identifier. |
| url | Base URL to the Cloud server. |
| options | Cloud options. |