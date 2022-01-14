---
title: App Extensions
slug: '/examples/app-extensions'
description: 'This page documents how to declare and use App Extension targets.'
---

### Product Types

iOS applications have a wide range of app extension types _(Notification Service, Intents, Widgets, etc...)_.

Some of those extensions have dedicated product types (e.g. `.messagesExtension`), while others may be represented
using the generic `.appExtension` product type.

For example, this is how a Notification Service Extension can be declared:

```swift
let project = Project(
    name: "App",
    targets: [
        Target(name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "NotificationServiceExtension"),
            ]
        ),
        Target(
            name: "NotificationServiceExtension",
            platform: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App.NotificationServiceExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.usernotifications.service",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService"
                ]
            ]),
            sources: "NotificationServiceExtension/**",
            dependencies: []
        ),
    ]
)
```

### Info Plist Keys

Different app extensions have a different set of `Info.plist` key requirements, one of the main ones is the `NSExtensionPointIdentifier` key that identifies the extension type.

For example, here is a list of some of the extension types and their corresponding identifier value:

| Extension            | `NSExtensionPointIdentifier`          |
| -------------------- | ------------------------------------- |
| Intents Extension    | `com.apple.intents-service`           |
| Intents UI Extension | `com.apple.intents-ui-service`        |
| Notification Service | `com.apple.usernotifications.service` |
| Widgets Extension    | `com.apple.widgetkit-extension`       |

Knowing the different key/value requirements may be needed when leveraging the auto-generated `Info.plist` file _(see [Info Plist](manifests/project.md))_.

To find out what the identifier for an extension type is or any other required key, you can examine the values within an existing `Info.plist` file _(if one exists)_,
or create a new sample project using the Xcode UI with the desired app extension target and examine the `Info.plist` file created by Xcode.

### Associating Extensions With Applications

To associate or include extensions within an application, the application target needs to declare a dependency on the corresponding extension targets.

For example:

```swift
let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "NotificationServiceExtension"),
                .target(name: "WidgetExtension"),
                // …
            ]
        ),
        // …
    ]
)
```
