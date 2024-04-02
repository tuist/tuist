**ENUM**

# `DefaultSettings`

```swift
public enum DefaultSettings: Codable, Equatable
```

Specifies the default set of settings applied to all the projects and targets.
The default settings can be overridden via `Settings base: SettingsDictionary`
and `Configuration settings: SettingsDictionary`.

## Cases
### `recommended(excluding:)`

```swift
case recommended(excluding: Set<String> = [])
```

Recommended settings including warning flags to help you catch some of the bugs at the early stage of development. If you
need to override certain settings in a `Configuration` it's possible to add those keys to `excluding`.

### `essential(excluding:)`

```swift
case essential(excluding: Set<String> = [])
```

A minimal set of settings to make the project compile without any additional settings for example `PRODUCT_NAME` or
`TARGETED_DEVICE_FAMILY`. If you need to override certain settings in a Configuration it's possible to add those keys to
`excluding`.

### `none`

```swift
case none
```

Tuist won't generate any build settings for the target or project.
