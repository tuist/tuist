---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# السجل {#registry}

كلما زاد عدد التبعيات، زاد الوقت اللازم لحلها. في حين أن مديري الحزم الأخرى مثل
[CocoaPods] (https://cocoapods.org/) أو [npm] (https://www.npmjs.com/) مركزية،
فإن Swift Package Manager ليس كذلك. وبسبب ذلك، يحتاج SwiftPM إلى حل التبعيات عن
طريق إجراء استنساخ عميق لكل مستودع، الأمر الذي قد يستغرق وقتًا طويلاً ويستهلك
ذاكرة أكثر من النهج المركزي. لمعالجة هذه المشكلة، يوفر تويست تطبيقًا لـ [سجل
الحزم]
(https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)،
بحيث يمكنك تنزيل الالتزامات التي تحتاجها _بالفعل_. تستند الحزم في السجل على
[فهرس حزمة سويفت] (https://swiftpackageindex.com/) - إذا تمكنت من العثور على
حزمة هناك، فإن الحزمة متوفرة أيضًا في سجل تويست. بالإضافة إلى ذلك، يتم توزيع
الحزم في جميع أنحاء العالم باستخدام مخزن حافة لأدنى حد من زمن الاستجابة عند
حلها.

## الاستخدام {#usage}

لإعداد السجل، قم بتشغيل الأمر التالي في دليل مشروعك:

```bash
tuist registry setup
```

يقوم هذا الأمر بإنشاء ملف تكوين السجل الذي يمكّن السجل لمشروعك. تأكد من التزام
هذا الملف حتى يتمكن فريقك أيضًا من الاستفادة من السجل.

### المصادقة (اختياري) {#authentication}

المصادقة **اختياري**. بدون المصادقة، يمكنك استخدام السجل بحد معدل **1000 طلب في
الدقيقة** لكل عنوان IP. للحصول على حد معدل أعلى للمعدل **20,000 طلب في الدقيقة**
، يمكنك المصادقة عن طريق تشغيل:

```bash
tuist registry login
```

:::: المعلومات
<!-- -->
تتطلب المصادقة حساب
<LocalizedLink href="/guides/server/accounts-and-projects">تويست
ومشروع</LocalizedLink>.
<!-- -->
:::

### حل التبعيات {#resolving-dependencies}

لحل التبعيات من السجل بدلاً من التحكم في المصدر، تابع القراءة بناءً على إعداد
مشروعك:
- <LocalizedLink href="/guides/features/registry/xcode-project">مشروع
  Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">مشروع تم
  إنشاؤه مع تكامل حزمة Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">مشروع تم
  إنشاؤه باستخدام تكامل الحزمة المستند إلى XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">الحزمة
  السريعة</LocalizedLink>

لإعداد السجل على CI، اتبع هذا الدليل:
<LocalizedLink href="/guides/features/registry/continuous-integration">التكامل
المستمر</LocalizedLink>.

### معرّفات سجل الحزمة {#package-registry-identifiers}

عند استخدام معرّفات سجل الحزمة في ملف `Package.swift` أو `Project.swift` ، يجب
تحويل عنوان URL الخاص بالحزمة إلى اصطلاح السجل. يكون معرّف السجل دائمًا على شكل
`{المنظمة}.{مستودع}`. على سبيل المثال، لاستخدام السجل للحزمة
`https://github.com/pointfreeco/swift-composable-architecture` ، سيكون معرّف سجل
الحزمة `pointfreeco.swift-composable-architecture`.

:::: المعلومات
<!-- -->
لا يمكن أن يحتوي المعرف على أكثر من نقطة واحدة. إذا كان اسم المستودع يحتوي على
نقطة، يتم استبداله بشرطة سفلية. على سبيل المثال، سيكون للحزمة
`https://github.com/groue/GRDB.swift https://github.com/groue/GRDB.swift` معرّف
السجل `groue.GRDB_swift`.
<!-- -->
:::
