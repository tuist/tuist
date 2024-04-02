**STRUCT**

# `PluginLocation`

```swift
public struct PluginLocation: Codable, Equatable
```

A location to a plugin, either local or remote.

## Properties
### `type`

```swift
public var type: LocationType
```

The type of location `local` or `git`.

## Methods
### `local(path:)`

```swift
public static func local(path: Path) -> Self
```

A `Path` to a directory containing a `Plugin` manifest.

Example:
```
.local(path: "/User/local/bin")
```

### `git(url:tag:directory:releaseUrl:)`

```swift
public static func git(url: String, tag: String, directory: String? = nil, releaseUrl: String? = nil) -> Self
```

A `URL` to a `git` repository pointing at a `tag`.
You can also specify a custom directory in case the plugin is not located at the root of the repository.
You can also specify a custom release URL from where the plugin binary should be downloaded. If not specified,
it defaults to the GitHub release URL. Note that the URL should be publicly reachable.

Example:
```
.git(url: "https://git/plugin.git", tag: "1.0.0", directory: "PluginDirectory")
```

### `git(url:sha:directory:)`

```swift
public static func git(url: String, sha: String, directory: String? = nil) -> Self
```

A `URL` to a `git` repository pointing at a commit `sha`.
You can also specify a custom directory in case the plugin is not located at the root of the repository.

Example:
```
.git(url: "https://git/plugin.git", sha: "d06b4b3d")
```
