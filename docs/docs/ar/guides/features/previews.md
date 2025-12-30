---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# المعاينات {#previews}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع تويست</LocalizedLink>
<!-- -->
:::

عند إنشاء تطبيق ما، قد ترغب في مشاركته مع الآخرين للحصول على تعليقاتهم.
تقليديًا، هذا شيء تقوم به الفرق من خلال بناء تطبيقاتها وتوقيعها ودفعها إلى منصات
مثل [TestFlight] من Apple [TestFlight]
(https://developer.apple.com/testflight/). ومع ذلك، يمكن أن تكون هذه العملية
مرهقة وبطيئة، خاصةً عندما تبحث فقط عن تعليقات سريعة من زميل أو صديق.

لجعل هذه العملية أكثر بساطة، يوفر Tuist طريقة لإنشاء معاينات لتطبيقاتك ومشاركتها
مع أي شخص.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
عند الإنشاء للجهاز، تقع على عاتقك حاليًا مسؤولية ضمان توقيع التطبيق بشكل صحيح.
نخطط لتبسيط هذا الأمر في المستقبل.
<!-- -->
:::

:::: code-group
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
::::

سينشئ الأمر رابطًا يمكنك مشاركته مع أي شخص لتشغيل التطبيق - إما على جهاز محاكاة
أو جهاز فعلي. كل ما عليهم فعله هو تشغيل الأمر أدناه:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

عند مشاركة ملف `.ipa` ، يمكنك تنزيل التطبيق مباشرة من الجهاز المحمول باستخدام
رابط المعاينة. تكون الروابط إلى `.ipa` معاينات بشكل افتراضي _عام_. في المستقبل،
سيكون لديك خيار لجعلها خاصة، بحيث يحتاج مستلم الرابط إلى المصادقة باستخدام حساب
Tuist الخاص به لتنزيل التطبيق.

`يمكّنك tuist run` أيضًا من تشغيل أحدث معاينة استنادًا إلى محدد مثل `أحدث` أو
اسم الفرع أو تجزئة التزام معين:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
تأكد من أن `CFBundleVersion` (إصدار الإنشاء) فريد من نوعه من خلال الاستفادة من رقم تشغيل CI الذي يعرضه معظم موفري CI. على سبيل المثال، في GitHub Actions، يمكنك تعيين `CFBundleVersion` إلى المتغير <code v-pre>${{ github.run_number }}</code>.

سيفشل تحميل معاينة بنفس الإصدار الثنائي (البناء) ونفس `CFBundleVersion`.
<!-- -->
:::

## المسارات {#tracks}

تسمح لك المسارات بتنظيم معايناتك في مجموعات مسماة. على سبيل المثال، قد يكون لديك
مسار `بيتا` للمختبرين الداخليين ومسار `ليلاً` للإصدارات الآلية. يتم إنشاء
المسارات بشكل كسول - ما عليك سوى تحديد اسم المسار عند المشاركة، وسيتم إنشاؤه
تلقائيًا إذا لم يكن موجودًا.

لمشاركة معاينة على مسار محدد، استخدم الخيار `- المسار`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

هذا مفيد لـ
- **تنظيم المعاينات**: تجميع المعاينات حسب الغرض (على سبيل المثال، `بيتا` ،
  `ليلي` ، `داخلي`)
- **التحديثات داخل التطبيق**: تستخدم مجموعة أدوات تطوير البرمجيات (Tuist SDK)
  المسارات لتحديد التحديثات التي يجب إخطار المستخدمين بها
- **تصفية**: العثور على المعاينات وإدارتها بسهولة حسب المسار في لوحة معلومات
  Tuist

::: warning PREVIEWS' VISIBILITY
<!-- -->
يمكن فقط للأشخاص الذين لديهم حق الوصول إلى المؤسسة التي ينتمي إليها المشروع
الوصول إلى المعاينات. نخطط لإضافة دعم للروابط المنتهية الصلاحية.
<!-- -->
:::

## تطبيق تويست ماك أو إس {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

لجعل تشغيل معاينات تويست أسهل، قمنا بتطوير تطبيق شريط قوائم نظام التشغيل Tuist
macOS. بدلاً من تشغيل المعاينات عبر Tuist CLI، يمكنك [تنزيل]
(https://tuist.dev/download) تطبيق macOS. يمكنك أيضًا تثبيت التطبيق عن طريق
تشغيل `brew install - cask tuist/tuist/Tuist/Tuist`.

عندما تنقر الآن على "تشغيل" في صفحة المعاينة، سيقوم تطبيق macOS بتشغيله تلقائيًا
على الجهاز المحدد حاليًا.

::: warning REQUIREMENTS
<!-- -->
يجب أن يكون لديك Xcode مثبتًا محليًا وأن يكون مثبتًا على نظام macOS 14 أو أحدث.
<!-- -->
:::

## تطبيق تويست iOS {#tuist-ios-app}

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

::: warning GIT PLATFORM INTEGRATION REQUIRED
<!-- -->
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج <LocalizedLink href="/guides/server/accounts-and-projects">مشروعك Tuist</LocalizedLink> مع <LocalizedLink href="/guides/server/authentication">منصة Git</LocalizedLink>.
<!-- -->
:::

يجب أن يكون اختبار الوظائف الجديدة جزءًا من أي مراجعة للكود. لكن الاضطرار إلى
إنشاء تطبيق محليًا يضيف احتكاكًا غير ضروري، وغالبًا ما يؤدي إلى تخطي المطورين
لاختبار الوظائف على أجهزتهم على الإطلاق. ولكن *ماذا لو احتوى كل طلب سحب على رابط
للبناء الذي من شأنه تشغيل التطبيق تلقائيًا على الجهاز الذي حددته في تطبيق Tuist
macOS؟*

بمجرد توصيل مشروع Tuist الخاص بك بمنصة Git الخاصة بك مثل [GitHub]
(https://github.com)، أضف <LocalizedLink href="/cli/share">`tuist share
MyApp`</LocalizedLink> إلى سير عمل CI الخاص بك. سيقوم Tuist بعد ذلك بنشر رابط
معاينة مباشرة في طلبات السحب الخاصة بك: ![تعليق تطبيق GitHub مع رابط معاينة
Tuist](/images/guides/features/github-app-with-preview.png)


## إشعارات التحديثات داخل التطبيق {#in-app-update-notifications}

تُمكِّن [Tuist SDK] (https://github.com/tuist/sdk) تطبيقك من اكتشاف وقت توفر
إصدار معاينة أحدث وإعلام المستخدمين. هذا مفيد لإبقاء المختبرين على أحدث إصدار.

تتحقق SDK من التحديثات داخل نفس **معاينة المسار**. عند مشاركة معاينة مع مسار
صريح باستخدام `- المسار` ، ستبحث SDK عن التحديثات على هذا المسار. إذا لم يتم
تحديد أي مسار، فسيتم استخدام فرع git كمسار - لذا فإن المعاينة التي تم إنشاؤها من
الفرع الرئيسي `` الرئيسي ستُعلم فقط بالمعاينات الأحدث التي تم إنشاؤها أيضًا من
`الرئيسي`.

### التركيب {#installation}

أضف Tuist SDK كجزء تابع لحزمة سويفت:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### مراقبة التحديثات {#monitor-updates}

استخدم `monitorPreviewUpdates` للتحقق بشكل دوري من إصدارات المعاينة الجديدة:

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

### التحقق من تحديث واحد {#single-check}

للتحقق من التحديث اليدوي:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### إيقاف مراقبة التحديثات {#stop-monitoring}

`يُرجِع موقع MonitorPreviewUpdates` مهمة `مهمة` يمكن إلغاؤها:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
يتم تعطيل التحقق من التحديث تلقائياً على أجهزة المحاكاة وإصدارات App Store.
<!-- -->
:::

## شارة README {#readme-badge}

لجعل معاينات تويست أكثر وضوحًا في مستودعك، يمكنك إضافة شارة إلى ملف `README`
الذي يشير إلى أحدث معاينة تويست:

[! [معاينة تويست]
(https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)]
(https://tuist.dev/Dimillian/IcySky/previews/latest)

لإضافة الشارة إلى `README` الخاص بك، استخدم العلامات التالية واستبدل مقابض
الحساب والمشروع بمقابضك الخاصة:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

إذا كان مشروعك يحتوي على تطبيقات متعددة بمعرّفات حزم مختلفة، يمكنك تحديد معاينة
التطبيق المراد الربط به عن طريق إضافة معلمة استعلام `معرف الحزمة`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## الأتمتة {#automations}

يمكنك استخدام العلامة `--json` للحصول على مخرجات JSON من الأمر `tuist share`:
```
tuist share --json
```

يعد إخراج JSON مفيدًا لإنشاء عمليات أتمتة مخصصة، مثل نشر رسالة Slack باستخدام
موفر CI الخاص بك. يحتوي JSON على مفتاح `url` مع رابط المعاينة الكامل ومفتاح
`qrCodeURL` مع عنوان URL لصورة رمز الاستجابة السريعة لتسهيل تنزيل المعاينات من
جهاز حقيقي. فيما يلي مثال على إخراج JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
