---
{
  "title": "Generated project with the Xcode package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the Xcode package integration."
}
---
# مشروع تم إنشاؤه مع تكامل الحزمة المستندة إلى XcodeProj {#generated-project-with-the-xcode-package-integration}

إذا كنت تستخدم التكامل الافتراضي <LocalizedLink href="/guides/features/projects/dependencies#xcodes-default-integration">لـ Xcode</LocalizedLink> للحزم مع مشاريع تويست، فأنت بحاجة إلى استخدام معرّف السجل بدلاً من عنوان URL عند إضافة حزمة:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```
