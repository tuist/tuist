**ENUM**

# `PluginLocation.LocationType`

```swift
public enum LocationType: Codable, Equatable
```

## Cases
### `local(path:)`

```swift
case local(path: Path)
```

### `gitWithTag(url:tag:directory:releaseUrl:)`

```swift
case gitWithTag(url: String, tag: String, directory: String?, releaseUrl: String?)
```

### `gitWithSha(url:sha:directory:)`

```swift
case gitWithSha(url: String, sha: String, directory: String?)
```
