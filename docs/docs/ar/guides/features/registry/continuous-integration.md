---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# التكامل المستمر (CI) {#continuous-integration-ci}

لاستخدام السجل على CI الخاص بك، عليك التأكد من تسجيل الدخول إلى السجل عن طريق
تشغيل `tuist registry login` كجزء من سير عملك.

::: info ONLY XCODE INTEGRATION
<!-- -->
لا يلزم إنشاء سلسلة مفاتيح جديدة مسبقًا إلا إذا كنت تستخدم تكامل حزم Xcode.
<!-- -->
:::

نظرًا لأن بيانات اعتماد التسجيل مخزنة في سلسلة مفاتيح، يجب التأكد من إمكانية
الوصول إلى سلسلة المفاتيح في بيئة CI. لاحظ أن بعض مزودي CI أو أدوات الأتمتة مثل
[Fastlane](https://fastlane.tools/) يقومون بالفعل بإنشاء سلسلة مفاتيح مؤقتة أو
يوفرون طريقة مدمجة لإنشاء واحدة. ومع ذلك، يمكنك أيضًا إنشاء واحدة عن طريق إنشاء
خطوة مخصصة باستخدام الكود التالي:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` سيقوم بعد ذلك بتخزين بيانات الاعتماد في سلسلة المفاتيح
الافتراضية. تأكد من إنشاء سلسلة المفاتيح الافتراضية وإلغاء قفلها _قبل تشغيل_
`tuist registry login`.

بالإضافة إلى ذلك، عليك التأكد من تعيين متغير البيئة `TUIST_TOKEN`. يمكنك إنشاء
متغير بالرجوع إلى الوثائق
<LocalizedLink href="/guides/server/authentication#as-a-project">هنا</LocalizedLink>.

قد يبدو مثال سير العمل لـ GitHub Actions كما يلي:
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

تكون عمليات التحليل النظيفة/الباردة أسرع قليلاً مع السجل الخاص بنا، ويمكنك تجربة
تحسينات أكبر إذا حافظت على التبعيات التي تم تحليلها عبر عمليات إنشاء CI. لاحظ
أنه بفضل السجل، يكون حجم الدليل الذي تحتاج إلى تخزينه واستعادته أصغر بكثير مما
لو لم يكن هناك سجل، مما يستغرق وقتًا أقل بكثير. لتخزين التبعيات مؤقتًا عند
استخدام تكامل حزمة Xcode الافتراضي، فإن أفضل طريقة هي تحديد
`clonedSourcePackagesDirPath` مخصص عند حل التبعيات عبر `xcodebuild`. يمكن القيام
بذلك عن طريق إضافة ما يلي إلى ملف `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

بالإضافة إلى ذلك، ستحتاج إلى العثور على مسار حزمة `Package.resolved`. يمكنك
الحصول على المسار عن طريق تشغيل `ls **/Package.resolved`. يجب أن يبدو المسار كما
يلي `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

بالنسبة لحزم Swift والتكامل المستند إلى XcodeProj، يمكننا استخدام الدليل
الافتراضي `.build` الموجود إما في جذر المشروع أو في الدليل `Tuist`. تأكد من صحة
المسار عند إعداد خط الأنابيب.

فيما يلي مثال على سير عمل GitHub Actions لحل التبعيات وتخزينها مؤقتًا عند
استخدام تكامل حزمة Xcode الافتراضي:
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
