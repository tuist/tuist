**STRUCT**

# `PrivacyManifest`

**Contents**

- [Properties](#properties)
  - `tracking`
  - `trackingDomains`
  - `collectedDataTypes`
  - `accessedApiTypes`
- [Methods](#methods)
  - `privacyManifest(tracking:trackingDomains:collectedDataTypes:accessedApiTypes:)`

```swift
public struct PrivacyManifest: Codable, Equatable, Sendable
```

Describe the data your app or third-party SDK collects and the reasons required APIs it uses.

## Properties
### `tracking`

```swift
public var tracking: Bool
```

A Boolean that indicates whether your app or third-party SDK uses data for tracking as defined under the App
Tracking Transparency framework. For more information, see [User Privacy and Data
Use](https://developer.apple.com/app-store/user-privacy-and-data-use/).

### `trackingDomains`

```swift
public var trackingDomains: [String]
```

An array of strings that lists the internet domains your app or third-party SDK connects to that
engage in tracking. If the user has not granted tracking permission through the App Tracking Transparency framework,
network requests to these domains fail and your app receives an error. If you set `tracking` to true then you need to
provide at least one internet domain in NSPrivacyTrackingDomains; otherwise, you can provide zero or more domains.

### `collectedDataTypes`

```swift
public var collectedDataTypes: [[String: Plist.Value]]
```

An array of dictionaries that describes the data types your app or third-party SDK collects. For
information on the keys and values to use in the dictionaries, see [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_data_use_in_privacy_manifests).

### `accessedApiTypes`

```swift
public var accessedApiTypes: [[String: Plist.Value]]
```

An array of dictionaries that describe the API types your app or third-party SDK accesses that have
been designated as APIs that require reasons to access. For information on the keys and values to use in the dictionaries,
see [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api).

## Methods
### `privacyManifest(tracking:trackingDomains:collectedDataTypes:accessedApiTypes:)`

```swift
public static func privacyManifest(
    tracking: Bool,
    trackingDomains: [String],
    collectedDataTypes: [[String: Plist.Value]],
    accessedApiTypes: [[String: Plist.Value]]
) -> Self
```

Returns a PrivacyManifest.
- Parameter tracking: A Boolean that indicates whether your app or third-party SDK uses data for tracking.
- Parameter trackingDomains: An array of strings that lists the internet domains your app or third-party SDK connects to
that engage in tracking.
- Parameter collectedDataTypes: An array of dictionaries that describes the data types your app or third-party SDK
collects.
- Parameter accessedApiTypes: An array of dictionaries that describe the API types your app or third-party SDK accesses
that have
been designated as APIs that require reasons to access.
- Returns: PrivacyManifest.

#### Parameters

| Name | Description |
| ---- | ----------- |
| tracking | A Boolean that indicates whether your app or third-party SDK uses data for tracking. |
| trackingDomains | An array of strings that lists the internet domains your app or third-party SDK connects to that engage in tracking. |
| collectedDataTypes | An array of dictionaries that describes the data types your app or third-party SDK collects. |
| accessedApiTypes | An array of dictionaries that describe the API types your app or third-party SDK accesses that have been designated as APIs that require reasons to access. |