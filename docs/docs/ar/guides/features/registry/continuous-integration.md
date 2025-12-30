---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# التكامل المستمر (CI) {#continuous-integration-ci}

لاستخدام السجل على CI الخاص بك، تحتاج إلى التأكد من تسجيل الدخول إلى السجل عن
طريق تشغيل `tuist تسجيل الدخول إلى السجل` كجزء من سير عملك.

::: info ONLY XCODE INTEGRATION
<!-- -->
لا يلزم إنشاء سلسلة مفاتيح جديدة غير مؤمّنة مسبقًا إلا إذا كنت تستخدم تكامل حزم
Xcode.
<!-- -->
:::

نظرًا لأنه يتم تخزين بيانات اعتماد السجل في سلسلة مفاتيح، فأنت بحاجة إلى التأكد
من إمكانية الوصول إلى سلسلة المفاتيح في بيئة CI. لاحظ أن بعض موفري CI أو أدوات
الأتمتة مثل [Fastlane] (https://fastlane.tools/) تنشئ بالفعل سلسلة مفاتيح مؤقتة
أو توفر طريقة مدمجة لكيفية إنشاء واحدة. ومع ذلك، يمكنك أيضًا إنشاء واحدة من خلال
إنشاء خطوة مخصصة باستخدام التعليمات البرمجية التالية:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`` سيتم بعد ذلك تخزين بيانات الاعتماد في سلسلة المفاتيح الافتراضية. تأكد من
إنشاء سلسلة المفاتيح الافتراضية وإلغاء قفلها _قبل تشغيل_ `تسجيل الدخول إلى سجل
tuist`.

بالإضافة إلى ذلك، تحتاج إلى التأكد من تعيين متغير البيئة `TUIST_TOKEN`. يمكنك
إنشاء واحد باتباع الوثائق
<LocalizedLink href="/guides/server/authentication#as-a-project">
هنا</LocalizedLink>.

مثال على سير العمل لإجراءات GitHub يمكن أن يبدو بعد ذلك على النحو التالي:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### الدقة التزايدية عبر البيئات {#incremental-resolution-across-environments}

تكون عمليات الحل النظيف/البارد أسرع قليلاً مع السجل الخاص بنا، ويمكنك تجربة
تحسينات أكبر إذا واصلت التبعيات التي تم حلها عبر إنشاءات CI. لاحظ أنه بفضل
السجل، يكون حجم الدليل الذي تحتاج إلى تخزينه واستعادته أصغر بكثير مما هو عليه
بدون السجل، مما يستغرق وقتًا أقل بكثير. لتخزين التبعيات مؤقتًا عند استخدام تكامل
حزمة Xcode الافتراضية، فإن أفضل طريقة هي تحديد `clonedSourcePackagesDirPath` عند
حل التبعيات عبر `xcodebuild`. يمكن القيام بذلك عن طريق إضافة ما يلي إلى ملف
`Config.swift` الخاص بك:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

بالإضافة إلى ذلك، ستحتاج إلى العثور على مسار `Package.resolved`. يمكنك الحصول
على المسار عن طريق تشغيل `ls ** / Package.resolved`. يجب أن يبدو المسار مثل
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

بالنسبة لحزم Swift والتكامل المستند إلى XcodeProj، يمكننا استخدام الدليل
الافتراضي `.build` الموجود إما في جذر المشروع أو في الدليل `Tuist`. تأكد من صحة
المسار عند إعداد خط الأنابيب الخاص بك.

فيما يلي مثال على سير عمل إجراءات GitHub لحل التبعيات وتخزينها مؤقتًا عند
استخدام تكامل حزمة Xcode الافتراضية:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
