---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# ذاكرة تخزين Xcode المؤقتة {#xcode-cache}

يوفر Tuist الدعم لذاكرة التخزين المؤقتة لتجميع Xcode، مما يسمح للفرق بمشاركة
عناصر التجميع من خلال الاستفادة من إمكانات التخزين المؤقت لنظام البناء.

## الإعداد {#setup}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
- Xcode 26.0 أو أحدث
<!-- -->
:::

إذا لم يكن لديك حساب Tuist ومشروع بالفعل، يمكنك إنشاء واحد عن طريق تشغيل:

```bash
tuist init
```

بمجرد حصولك على ملف `Tuist.swift` الذي يشير إلى `fullHandle` ، يمكنك إعداد
التخزين المؤقت لمشروعك عن طريق تشغيل:

```bash
tuist setup cache
```

يُنشئ هذا الأمر
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
لتشغيل خدمة ذاكرة التخزين المؤقتة المحلية عند بدء التشغيل التي يستخدمها [نظام
البناء](https://github.com/swiftlang/swift-build) Swift لمشاركة عناصر التجميع.
يجب تشغيل هذا الأمر مرة واحدة في كل من بيئتك المحلية وبيئة CI.

لإعداد ذاكرة التخزين المؤقت على CI، تأكد من أنك
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
المستخدم **** لأنها لا تظهر مباشرة في واجهة مستخدم إعدادات البناء في Xcode:

::: info SOCKET PATH
<!-- -->
سيتم عرض مسار المقبس عند تشغيل `tuist setup cache`. وهو يعتمد على المعالج الكامل
لمشروعك مع استبدال الشرطات المائلة بشرطات سفلية.
<!-- -->
:::

يمكنك أيضًا تحديد هذه الإعدادات عند تشغيل `xcodebuild` عن طريق إضافة العلامات
التالية، مثل:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
لا داعي لإجراء الإعدادات يدويًا إذا كان مشروعك قد تم إنشاؤه بواسطة Tuist.

في هذه الحالة، كل ما عليك هو إضافة `enableCaching: true` إلى ملف `Tuist.swift`:
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

لتمكين التخزين المؤقت في بيئة CI الخاصة بك، تحتاج إلى تشغيل نفس الأمر كما في
البيئات المحلية: `tuist setup cache`.

للمصادقة، يمكنك استخدام إما
<LocalizedLink href="/guides/server/authentication#oidc-tokens">مصادقة
OIDC</LocalizedLink> (موصى بها لموفري CI المدعومين) أو
<LocalizedLink href="/guides/server/authentication#account-tokens">رمز
حساب</LocalizedLink> عبر متغير بيئة `TUIST_TOKEN`.

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

انظر دليل
<LocalizedLink href="/guides/integrations/continuous-integration">التكامل
المستمر</LocalizedLink> لمزيد من الأمثلة، بما في ذلك المصادقة القائمة على الرموز
المميزة ومنصات التكامل المستمر الأخرى مثل Xcode Cloud و CircleCI و Bitrise و
Codemagic.
