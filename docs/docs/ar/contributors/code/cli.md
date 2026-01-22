---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

المصدر:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
و
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## ما الغرض منه {#what-it-is-for}

CLI هو قلب Tuist. فهو يتولى إنشاء المشاريع وسير العمل الآلي (الاختبار والتشغيل
والرسم البياني والتفتيش)، ويوفر واجهة لخادم Tuist لميزات مثل المصادقة والذاكرة
المؤقتة والرؤى والمعاينات والتسجيل والاختبار الانتقائي.

## كيفية المساهمة {#how-to-contribute}

### المتطلبات {#requirements}

- macOS 14.0+
- Xcode 26+

### قم بالإعداد محليًا {#set-up-locally}

- انسخ المستودع: `git clone git@github.com:tuist/tuist.git`
- قم بتثبيت Mise باستخدام [نص التثبيت
  الرسمي](https://mise.jdx.dev/getting-started.html) (وليس Homebrew) وقم بتشغيل
  `mise install`
- قم بتثبيت تبعيات Tuist: `tuist install`
- قم بإنشاء مساحة العمل: `tuist generate`

يتم فتح المشروع الذي تم إنشاؤه تلقائيًا. إذا كنت بحاجة إلى إعادة فتحه لاحقًا،
فقم بتشغيل `open Tuist.xcworkspace`.

::: info XED .
<!-- -->
إذا حاولت فتح المشروع باستخدام `xed .` ، فسيتم فتح الحزمة، وليس مساحة العمل التي
أنشأتها Tuist. استخدم `Tuist.xcworkspace`.
<!-- -->
:::

### قم بتشغيل Tuist {#run-tuist}

#### من Xcode {#from-xcode}

قم بتحرير ملف `tuist` scheme وقم بتعيين الحجج مثل `generate --no-open`. قم
بتعيين دليل العمل إلى جذر المشروع (أو استخدم `--path`).

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
يعتمد CLI على إنشاء مشروع `ProjectDescription`. إذا فشل في التشغيل، فقم أولاً
بإنشاء مخطط `Tuist-Workspace`.
<!-- -->
:::

#### من المحطة الطرفية {#from-the-terminal}

قم أولاً بإنشاء مساحة العمل:

```bash
tuist generate --no-open
```

ثم قم بإنشاء ملف `tuist` القابل للتنفيذ باستخدام Xcode وقم بتشغيله من
DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

أو عبر Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
