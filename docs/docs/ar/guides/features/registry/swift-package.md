---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# حزم سويفت {#حزم سويفت}

إذا كنت تعمل على حزمة Swift، يمكنك استخدام علامة `--replace-scm-with-registry`
لحل التبعيات من السجل إذا كانت متوفرة:

```bash
swift package --replace-scm-with-registry resolve
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
