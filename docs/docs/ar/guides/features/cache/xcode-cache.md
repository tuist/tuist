---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# ذاكرة تخزين Xcode المؤقتة {#xcode-cache}

يوفر Tuist دعمًا لذاكرة التخزين المؤقتة لتجميع Xcode، مما يسمح للفرق بمشاركة
مخرجات التجميع من خلال الاستفادة من قدرات التخزين المؤقت لنظام البناء.

## الإعداد {#setup}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  ومشروع</LocalizedLink>
- Xcode 26.0 أو أحدث
<!-- -->
:::

إذا لم يكن لديك حساب Tuist ومشروع بعد، يمكنك إنشاء واحد عن طريق تشغيل:

```bash
tuist init
```

بمجرد أن يكون لديك ملف `Tuist.swift` يشير إلى `fullHandle` ، يمكنك إعداد التخزين
المؤقت لمشروعك عن طريق تشغيل:

```bash
tuist setup cache
```

يُنشئ هذا الأمر
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
لتشغيل خدمة ذاكرة التخزين المؤقتة المحلية عند بدء التشغيل، والتي يستخدمها [نظام
البناء](https://github.com/swiftlang/swift-build) في Swift لمشاركة مكونات
التجميع. يجب تشغيل هذا الأمر مرة واحدة في كل من بيئتك المحلية وبيئة CI.

لإعداد ذاكرة التخزين المؤقتة على CI، تأكد من أنك
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">مصادق
عليه</LocalizedLink>.

### تكوين إعدادات إنشاء Xcode {#configure-xcode-build-settings}

أضف إعدادات البناء التالية إلى مشروع Xcode الخاص بك:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

لاحظ أن `COMPILATION_CACHE_REMOTE_SERVICE_PATH` و
`COMPILATION_CACHE_ENABLE_PLUGIN` يجب إضافتها كإعدادات بناء محددة من قبل
المستخدم **** لأنها غير معروضة مباشرة في واجهة مستخدم إعدادات البناء في Xcode:

::: info SOCKET PATH
<!-- -->
سيتم عرض مسار المقبس عند تشغيل `tuist setup cache`. وهو يعتمد على المعرف الكامل
لمشروعك مع استبدال الشرطات المائلة بعلامات التسطير.
<!-- -->
:::

يمكنك أيضًا تحديد هذه الإعدادات عند تشغيل `xcodebuild` بإضافة العلامات التالية،
مثل:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
لا حاجة إلى ضبط الإعدادات يدويًا إذا كان مشروعك قد تم إنشاؤه بواسطة Tuist.

في هذه الحالة، كل ما عليك هو إضافة `enableCaching: true` إلى ملف `Tuist.swift`
الخاص بك:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### التكامل المستمر {#continuous-integration}

لتمكين التخزين المؤقت في بيئة CI الخاصة بك، تحتاج إلى تشغيل نفس الأمر المستخدم
في البيئات المحلية: `tuist setup cache`.

للتوثيق، يمكنك استخدام إما
<LocalizedLink href="/guides/server/authentication#oidc-tokens">توثيق
OIDC</LocalizedLink> (موصى به لموفري CI المدعومين) أو
<LocalizedLink href="/guides/server/authentication#account-tokens">رمز
حساب</LocalizedLink> عبر متغير البيئة `TUIST_TOKEN`.

مثال على سير العمل لـ GitHub Actions باستخدام مصادقة OIDC:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

انظر <LocalizedLink href="/guides/integrations/continuous-integration">دليل
التكامل المستمر</LocalizedLink> لمزيد من الأمثلة، بما في ذلك المصادقة القائمة
على الرموز ومنصات التكامل المستمر الأخرى مثل Xcode Cloud وCircleCI وBitrise
وCodemagic.
