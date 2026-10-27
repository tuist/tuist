---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# مشروع تم إنشاؤه مع تكامل الحزمة المستندة إلى XcodeProj {#generated-project-with-the-xcodeprojbased-package-integration}

عند استخدام التكامل المستند إلى
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">
XcodeProj</LocalizedLink>، يمكنك استخدام العلامة ``--استبدال
-Scm-with-registry`` لحل التبعيات من السجل إذا كانت متوفرة. أضفها إلى ملف
`installOptions` في ملف `Tuist.swift` الخاص بك :
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

إذا كنت ترغب في التأكد من استخدام السجل في كل مرة تقوم فيها بحل التبعيات،
فستحتاج إلى تحديث `التبعيات` في ملف `Tuist/Package.swift` لاستخدام معرف السجل
بدلاً من عنوان URL. يكون معرّف السجل دائمًا على شكل `{المؤسسة}.{مستودع}`. على
سبيل المثال، لاستخدام السجل للحزمة `swift-composable-architecture` ، قم بما يلي:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
