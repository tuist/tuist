---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# علامات البيانات الوصفية {#metadata-tags}

مع تزايد حجم المشاريع وتعقيدها، قد يصبح العمل على قاعدة الكود بأكملها في وقت
واحد غير فعال. يوفر Tuist علامات بيانات وصفية **** كوسيلة لتنظيم الأهداف في
مجموعات منطقية والتركيز على أجزاء محددة من مشروعك أثناء التطوير.

## ما هي علامات البيانات الوصفية؟ {#what-are-metadata-tags}

علامات البيانات الوصفية هي علامات سلسلة يمكنك إرفاقها بالأهداف في مشروعك. وهي
بمثابة علامات تسمح لك بما يلي:

- **تجميع الأهداف ذات الصلة** - ضع علامة على الأهداف التي تنتمي إلى نفس الميزة
  أو الفريق أو الطبقة المعمارية
- **ركز على مساحة العمل الخاصة بك** - أنشئ مشاريع تتضمن فقط الأهداف ذات العلامات
  المحددة
- **حسّن سير عملك** - اعمل على ميزات محددة دون تحميل أجزاء غير ذات صلة من قاعدة
  الكود الخاصة بك
- **حدد الأهداف التي تريد الاحتفاظ بها كمصادر** - اختر مجموعة الأهداف التي تريد
  الاحتفاظ بها كمصادر عند التخزين المؤقت

يتم تعريف العلامات باستخدام خاصية `metadata` على الأهداف ويتم تخزينها كمصفوفة من
السلاسل.

## تحديد علامات البيانات الوصفية {#defining-metadata-tags}

يمكنك إضافة علامات إلى أي هدف في ملف تعريف مشروعك:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## التركيز على الأهداف الموسومة {#focusing-on-tagged-targets}

بمجرد وضع علامات على أهدافك، يمكنك استخدام الأمر `tuist generate` لإنشاء مشروع
مركّز يتضمن أهدافًا محددة فقط:

### التركيز حسب العلامة

استخدم علامة `: بادئة` لإنشاء مشروع يحتوي على جميع الأهداف المطابقة لعلامة
معينة:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### التركيز حسب الاسم

يمكنك أيضًا التركيز على أهداف محددة حسب الاسم:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### كيف يعمل التركيز

عند التركيز على الأهداف:

1. **الأهداف المضمنة** - الأهداف المطابقة لطلبك مضمنة في المشروع الذي تم إنشاؤه
2. **التبعيات** - يتم تضمين جميع تبعيات الأهداف المركزة تلقائيًا
3. **أهداف الاختبار** - يتم تضمين أهداف الاختبار للأهداف المركزة
4. **الاستبعاد** - يتم استبعاد جميع الأهداف الأخرى من مساحة العمل

وهذا يعني أنك تحصل على مساحة عمل أصغر حجمًا وأسهل في الإدارة تحتوي فقط على ما
تحتاجه للعمل على الميزة الخاصة بك.

## قواعد تسمية العلامات {#tag-naming-conventions}

على الرغم من أنه يمكنك استخدام أي سلسلة كعلامة، فإن اتباع قواعد تسمية متسقة
يساعد في الحفاظ على تنظيم علاماتك:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

استخدام البادئات مثل `feature:` ، `team:` ، أو `layer:` يجعل من السهل فهم الغرض
من كل علامة وتجنب تعارضات التسمية.

## علامات النظام {#system-tags}

يستخدم Tuist البادئة `tuist:` للعلامات التي يديرها النظام. يتم تطبيق هذه
العلامات تلقائيًا بواسطة Tuist ويمكن استخدامها في ملفات تعريف ذاكرة التخزين
المؤقت لاستهداف أنواع معينة من المحتوى الذي تم إنشاؤه.

### علامات النظام المتاحة

| الوسم               | الوصف                                                                                                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tuist:synthesized` | يتم تطبيقه على حزم مستهدفة مركبة ينشئها Tuist لمعالجة الموارد في المكتبات الثابتة والأطر الثابتة. توجد هذه الحزم لأسباب تاريخية لتوفير واجهات برمجة تطبيقات (API) للوصول إلى الموارد. |

### استخدام علامات النظام مع ملفات تعريف ذاكرة التخزين المؤقت

يمكنك استخدام علامات النظام في ملفات تعريف ذاكرة التخزين المؤقتة لتضمين أو
استبعاد الأهداف المركبة:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
تورث حزم الأهداف المركبة جميع العلامات من هدفها الأصلي بالإضافة إلى تلقي علامة
`tuist:synthesized`. هذا يعني أنه إذا قمت بتمييز مكتبة ثابتة بعلامة
`feature:auth` ، فستحتوي حزمة الموارد المركبة على كل من علامات `feature:auth` و
`tuist:synthesized`.
<!-- -->
:::

## استخدام العلامات مع مساعدات وصف المشروع {#using-tags-with-helpers}

يمكنك الاستفادة من
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink> لتوحيد طريقة تطبيق العلامات في مشروعك:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

ثم استخدمه في ملفات البيانات الخاصة بك:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## فوائد استخدام علامات البيانات الوصفية {#benefits}

### تجربة تطوير محسّنة

من خلال التركيز على أجزاء محددة من مشروعك، يمكنك:

- **تقليل حجم مشروع Xcode** - اعمل مع مشاريع أصغر حجمًا يمكن فتحها وتصفحها بشكل
  أسرع
- **تسريع عمليات البناء** - قم ببناء ما تحتاجه فقط لعملك الحالي
- **تحسين التركيز** - تجنب التشتيت من الكود غير ذي الصلة
- **تحسين الفهرسة** - يقوم Xcode بفهرسة كود أقل، مما يجعل الإكمال التلقائي أسرع

### تنظيم أفضل للمشروع

توفر العلامات طريقة مرنة لتنظيم قاعدة الكود الخاصة بك:

- **أبعاد متعددة** - ضع علامات على الأهداف حسب الميزة أو الفريق أو الطبقة أو
  النظام الأساسي أو أي بُعد آخر
- **لا تغييرات هيكلية** - أضف هيكلًا تنظيميًا دون تغيير تخطيط الدليل
- **المسائل المشتركة** - يمكن أن ينتمي هدف واحد إلى عدة مجموعات منطقية

### التكامل مع التخزين المؤقت

تعمل علامات البيانات الوصفية بسلاسة مع
<LocalizedLink href="/guides/features/cache">ميزات التخزين المؤقت في
Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## أفضل الممارسات {#best-practices}

1. **ابدأ ببساطة** - ابدأ بوضع علامة واحدة (على سبيل المثال، الميزات) وقم
   بالتوسيع حسب الحاجة
2. **كن متسقًا** - استخدم نفس قواعد التسمية في جميع ملفات البيانات الخاصة بك
3. **قم بتوثيق علاماتك** - احتفظ بقائمة بالعلامات المتاحة ومعانيها في وثائق
   مشروعك
4. **استخدم المساعدين** - استفد من مساعدين وصف المشروع لتوحيد تطبيق العلامات
5. **قم بالمراجعة بشكل دوري** - مع تطور مشروعك، قم بمراجعة وتحديث استراتيجية وضع
   العلامات الخاصة بك

## ميزات ذات صلة {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">مشاركة
  الكود</LocalizedLink> - استخدم أدوات مساعدة وصف المشروع لتوحيد استخدام
  العلامات
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - اجمع بين
  العلامات والتخزين المؤقت لتحقيق أداء بناء أمثل
- <LocalizedLink href="/guides/features/selective-testing">اختبار
  انتقائي</LocalizedLink> - قم بإجراء الاختبارات فقط للأهداف التي تم تغييرها
