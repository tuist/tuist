---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# معاينات {#previews}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
<!-- -->
:::

عند إنشاء تطبيق، قد ترغب في مشاركته مع الآخرين للحصول على تعليقاتهم. عادةً ما
يقوم الفريق بذلك عن طريق إنشاء التطبيق وتوقيعه ونشره على منصات مثل
[TestFlight](https://developer.apple.com/testflight/) من Apple. ومع ذلك، قد تكون
هذه العملية مرهقة وبطيئة، خاصةً إذا كنت تريد الحصول على تعليقات سريعة من زميل أو
صديق.

لتبسيط هذه العملية، يوفر Tuist طريقة لإنشاء معاينات لتطبيقاتك ومشاركتها مع أي
شخص.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
عند الإنشاء للجهاز، تقع على عاتقك حاليًا مسؤولية التأكد من توقيع التطبيق بشكل
صحيح. نخطط لتبسيط هذا الأمر في المستقبل.
<!-- -->
:::

:::: مجموعة الرموز
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

سيقوم الأمر بإنشاء رابط يمكنك مشاركته مع أي شخص لتشغيل التطبيق - سواء على جهاز
محاكاة أو جهاز حقيقي. كل ما عليهم فعله هو تشغيل الأمر التالي:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

عند مشاركة ملف `.ipa` ، يمكنك تنزيل التطبيق مباشرة من الجهاز المحمول باستخدام
رابط المعاينة. روابط معاينة `.ipa` هي بشكل افتراضي _private_ ، مما يعني أن
المستلم يحتاج إلى المصادقة باستخدام حساب Tuist الخاص به لتنزيل التطبيق. يمكنك
تغيير هذا إلى عام في إعدادات المشروع إذا كنت ترغب في مشاركة التطبيق مع أي شخص.

`tuist run` يتيح لك أيضًا تشغيل أحدث معاينة بناءً على محدد مثل `latest` أو اسم
الفرع أو هاش التزام محدد:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
تأكد من أن `CFBundleVersion` (إصدار البنية) فريد من خلال الاستفادة من رقم تشغيل
CI الذي يعرضه معظم مزودي CI. على سبيل المثال، في GitHub Actions، يمكنك تعيين
`CFBundleVersion` إلى المتغير <code v-pre>${{ github.run_number }}</code>.

سيفشل تحميل معاينة بنفس الملف الثنائي (البناء) ونفس CFBundleVersion `` .
<!-- -->
:::

## المسارات {#tracks}

تتيح لك المسارات تنظيم معايناتك في مجموعات مسماة. على سبيل المثال، قد يكون لديك
مسار `beta` للمختبرين الداخليين ومسار `nightly` للبنيات الآلية. يتم إنشاء
المسارات بشكل بطيء — ما عليك سوى تحديد اسم المسار عند المشاركة، وسيتم إنشاؤه
تلقائيًا إذا لم يكن موجودًا.

لمشاركة معاينة على مسار معين، استخدم خيار `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

هذا مفيد في الحالات التالية:
- **تنظيم المعاينات**: قم بتجميع المعاينات حسب الغرض (على سبيل المثال، `beta` ،
  `nightly` ، `internal`)
- **تحديثات داخل التطبيق**: يستخدم Tuist SDK المسارات لتحديد التحديثات التي يجب
  إخطار المستخدمين بها
- **تصفية**: ابحث عن المعاينات وأديرها بسهولة حسب المسار في لوحة تحكم Tuist

::: warning PREVIEWS' VISIBILITY
<!-- -->
لا يمكن الوصول إلى المعاينات إلا للأشخاص الذين لديهم حق الوصول إلى المنظمة التي
ينتمي إليها المشروع. نخطط لإضافة دعم للروابط التي تنتهي صلاحيتها.
<!-- -->
:::

## تطبيق Tuist macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

لتسهيل تشغيل Tuist Previews، قمنا بتطوير تطبيق Tuist macOS menu bar. بدلاً من
تشغيل Previews عبر Tuist CLI، يمكنك [تنزيل](https://tuist.dev/download) تطبيق
macOS. يمكنك أيضًا تثبيت التطبيق عن طريق تشغيل `brew install --cask
tuist/tuist/tuist`.

عندما تنقر الآن على "تشغيل" في صفحة المعاينة، سيقوم تطبيق macOS بتشغيله تلقائيًا
على الجهاز المحدد حاليًا.

:::: متطلبات التحذير
<!-- -->
يجب أن يكون Xcode مثبتًا محليًا وأن تكون تستخدم macOS 14 أو إصدار أحدث.
<!-- -->
:::

## تطبيق Tuist لنظام iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

على غرار تطبيق macOS، تعمل تطبيقات Tuist iOS على تبسيط الوصول إلى المعاينات
وتشغيلها.

## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

:::: تحذير التكامل مع منصة GIT مطلوب
<!-- -->
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج مشروعك
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
مع <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>منصة
<LocalizedLink href="/guides/server/authentication">Git.
<!-- -->
:::

يجب أن يكون اختبار الوظائف الجديدة جزءًا من أي مراجعة للكود. لكن الاضطرار إلى
إنشاء تطبيق محليًا يضيف صعوبات لا داعي لها، مما يؤدي غالبًا إلى تجاهل المطورين
لاختبار الوظائف على أجهزتهم تمامًا. ولكن *ماذا لو احتوى كل طلب سحب على رابط إلى
البنية التي ستشغل التطبيق تلقائيًا على الجهاز الذي حددته في تطبيق Tuist macOS؟*

بمجرد ربط مشروع Tuist بمنصة Git الخاصة بك مثل [GitHub](https://github.com)، أضف
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> إلى سير عمل
CI الخاص بك. سيقوم Tuist بعد ذلك بنشر رابط معاينة مباشرة في طلبات السحب الخاصة
بك: ![تعليق تطبيق GitHub مع رابط معاينة
Tuist](/images/guides/features/github-app-with-preview.png)


## إشعارات التحديث داخل التطبيق {#in-app-update-notifications}

يمكّن [Tuist SDK] (https://github.com/tuist/sdk) تطبيقك من اكتشاف وقت توفر إصدار
معاينة أحدث وإعلام المستخدمين. هذا مفيد لإبقاء المختبرين على أحدث إصدار.

يتحقق SDK من وجود تحديثات ضمن نفس مسار المعاينة **** . عند مشاركة معاينة مع مسار
صريح باستخدام `--track` ، سيبحث SDK عن تحديثات على هذا المسار. إذا لم يتم تحديد
أي مسار، فسيتم استخدام فرع git كمسار — لذا فإن المعاينة التي تم إنشاؤها من الفرع
الرئيسي `` ستقوم فقط بإخطار المعاينات الأحدث التي تم إنشاؤها أيضًا من الفرع
الرئيسي `` .

### التثبيت {#sdk-installation}

أضف Tuist SDK كاعتماد لحزمة Swift:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### راقب التحديثات {#sdk-monitor-updates}

استخدم `monitorPreviewUpdates` للتحقق بشكل دوري من وجود إصدارات معاينة جديدة:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### فحص تحديث واحد {#sdk-single-check}

للتحقق من التحديثات يدويًا:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### إيقاف مراقبة التحديثات {#sdk-stop-monitoring}

`monitorPreviewUpdates` يُرجع مهمة `Task` يمكن إلغاؤها:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

:::: المعلومات
<!-- -->
يتم تعطيل التحقق من التحديثات تلقائيًا على أجهزة المحاكاة وإصدارات App Store.
<!-- -->
:::

## شارة README {#readme-badge}

لجعل معاينات Tuist أكثر وضوحًا في مستودعك، يمكنك إضافة شارة إلى ملف
README` الخاص بـ `يشير إلى أحدث معاينة Tuist:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

لإضافة الشارة إلى ملف README الخاص بك على `` ، استخدم التخفيض التالي واستبدل
معرف الحساب والمشروع بمعرفك الخاص:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

إذا كان مشروعك يحتوي على عدة تطبيقات بمعرفات حزم مختلفة، يمكنك تحديد معاينة
التطبيق التي تريد الارتباط بها عن طريق إضافة معلمة استعلام `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## الأتمتة {#automations}

يمكنك استخدام علامة `--json` للحصول على مخرجات JSON من الأمر `tuist share`:
```
tuist share --json
```

يعد إخراج JSON مفيدًا لإنشاء عمليات أتمتة مخصصة، مثل نشر رسالة Slack باستخدام
مزود CI الخاص بك. يحتوي JSON على مفتاح url` ` مع رابط المعاينة الكامل ومفتاح
qrCodeURL` ` مع عنوان URL لصورة رمز QR لتسهيل تنزيل المعاينات من جهاز حقيقي.
فيما يلي مثال على إخراج JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
