**ENUM**

# `Package`

```swift
public enum Package: Equatable, Codable
```

A dependency of a Swift package.

A package dependency can be either:
    - remote: A Git URL to the source of the package,
    and a requirement for the version of the package.
    - local: A relative path to the package.

## Cases
### `remote(url:requirement:)`

```swift
case remote(url: String, requirement: Requirement)
```

### `local(path:)`

```swift
case local(path: Path)
```
