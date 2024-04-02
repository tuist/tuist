**ENUM**

# `Headers.AutomaticExclusionRule`

```swift
public enum AutomaticExclusionRule: Int, Codable
```

Determine how to resolve cases, when the same files found in different header scopes

## Cases
### `projectExcludesPrivateAndPublic`

```swift
case projectExcludesPrivateAndPublic
```

Project headers = all found - private headers - public headers

Order of tuist search:
 1) Public headers
 2) Private headers (with auto excludes all found public headers)
 3) Project headers (with excluding public/private headers)

 Also tuist doesn't ignore all excludes,
 which had been set by `excluding` param

### `publicExcludesPrivateAndProject`

```swift
case publicExcludesPrivateAndProject
```

Public headers = all found - private headers - project headers

Order of tuist search (reverse search):
 1) Project headers
 2) Private headers (with auto excludes all found project headers)
 3) Public headers (with excluding project/private headers)

 Also tuist doesn't ignore all excludes,
 which had been set by `excluding` param
