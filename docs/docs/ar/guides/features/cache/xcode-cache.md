---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# ذاكرة تخزين Xcode المؤقتة {#xcode-cache}

يوفر تويست دعمًا لذاكرة التخزين المؤقت لتجميع Xcode، مما يسمح للفرق بمشاركة
القطع الأثرية للتجميع من خلال الاستفادة من قدرات التخزين المؤقت لنظام الإنشاء.

## الإعداد {#setup}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع Tuist</LocalizedLink>
- Xcode 26.0 أو أحدث
<!-- -->
:::

إذا لم يكن لديك حساب ومشروع تويست بالفعل، يمكنك إنشاء حساب ومشروع عن طريق
التشغيل:

```bash
tuist init
```

بمجرد أن يكون لديك ملف `Tuist.swift.swift` الذي يشير إلى ملف `fullHandle` ،
يمكنك إعداد التخزين المؤقت لمشروعك عن طريق تشغيل:

```bash
tuist setup cache
```

ينشئ هذا الأمر [LaunchAgent]
(https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
لتشغيل خدمة تخزين مؤقت محلية عند بدء التشغيل يستخدمها [نظام البناء]
(https://github.com/swiftlang/swift-build) Swift لمشاركة القطع الأثرية للتجميع.
يجب تشغيل هذا الأمر مرة واحدة في كل من البيئات المحلية وبيئة التخزين المؤقت.

لإعداد ذاكرة التخزين المؤقت على CI، تأكد من أنك <LocalizedLink href="/guides/integrations/continuous-integration#authentication">مصادق</LocalizedLink>.

### تهيئة إعدادات إنشاء Xcode {#configure-xcode-build-settings}

أضف إعدادات الإنشاء التالية إلى مشروع Xcode الخاص بك:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

لاحظ أن `COMPILATION_CACHE_REMOTE_SERVICE_SERVICE_PATH` و
`COMPILATION_CACHE_ENABLE_PLUGIN` يجب إضافتها كإعدادات بناء **محددة من قبل
المستخدم** نظرًا لأنها غير مكشوفة مباشرة في واجهة مستخدم إعدادات البناء في
Xcode:

::: info SOCKET PATH
<!-- -->
سيتم عرض مسار المقبس عند تشغيل `tuist إعداد ذاكرة التخزين المؤقت`. وهو يستند إلى
المقبض الكامل لمشروعك مع استبدال الشرطات المائلة بشرطة سفلية.
<!-- -->
:::

يمكنك أيضًا تحديد هذه الإعدادات عند تشغيل `xcodebuild` عن طريق إضافة الأعلام
التالية، مثل

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

في هذه الحالة، كل ما تحتاجه هو إضافة `enableCaching: true` إلى ملف
`Tuist.swift.swift` الخاص بك :
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

لتمكين التخزين المؤقت في بيئة CI الخاصة بك، تحتاج إلى تشغيل نفس الأمر كما هو
الحال في البيئات المحلية: `tuist إعداد ذاكرة التخزين المؤقت`.

بالإضافة إلى ذلك، تحتاج إلى التأكد من تعيين متغير البيئة `TUIST_TOKEN`. يمكنك إنشاء واحد باتباع الوثائق <LocalizedLink href="/guides/server/authentication#as-a-project">هنا</LocalizedLink>. يجب أن يكون متغير البيئة `TUIST_TOKEN` موجودًا لخطوة الإنشاء الخاصة بك، لكننا نوصي بتعيينه لسير عمل CI بأكمله.

مثال على سير العمل لإجراءات GitHub يمكن أن يبدو بعد ذلك على النحو التالي:
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
