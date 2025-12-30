---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# علامات البيانات الوصفية {#metadata-tags}

مع نمو المشاريع من حيث الحجم والتعقيد، يمكن أن يصبح العمل مع قاعدة الرموز
بأكملها في وقت واحد غير فعال. يوفر تويست **علامات البيانات الوصفية** كطريقة
لتنظيم الأهداف في مجموعات منطقية والتركيز على أجزاء محددة من مشروعك أثناء
التطوير.

## ما هي علامات البيانات الوصفية؟ {#what-are-metadata-tags}

علامات البيانات الوصفية هي عبارة عن تسميات سلسلة يمكنك إرفاقها بالأهداف في
مشروعك. وهي بمثابة علامات تسمح لك بما يلي:

- **تجميع الأهداف ذات الصلة** - وسم الأهداف التي تنتمي إلى نفس الميزة أو الفريق
  أو الطبقة المعمارية
- **ركز مساحة عملك** - أنشئ مشاريع تتضمن فقط الأهداف التي تحمل علامات محددة
- **حسِّن سير عملك** - اعمل على ميزات محددة دون تحميل أجزاء غير ذات صلة من قاعدة
  التعليمات البرمجية الخاصة بك
- **حدد الأهداف التي تريد الاحتفاظ بها كمصادر** - اختر مجموعة الأهداف التي ترغب
  في الاحتفاظ بها كمصادر عند التخزين المؤقت

يتم تعريف العلامات باستخدام خاصية `metadata` على الأهداف ويتم تخزينها كمصفوفة من
السلاسل.

## تعريف علامات البيانات الوصفية {#defining-metadata-tags}

يمكنك إضافة علامات إلى أي هدف في بيان المشروع الخاص بك:

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

بمجرد أن تقوم بتمييز أهدافك، يمكنك استخدام الأمر `tuist gener` لإنشاء مشروع
مركّز يتضمن أهدافًا محددة فقط:

### التركيز حسب العلامة

استخدم العلامة `:` لإنشاء مشروع يحتوي على جميع الأهداف المطابقة لعلامة معينة:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### التركيز بالاسم

يمكنك أيضاً التركيز على أهداف محددة بالاسم:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### كيفية عمل التركيز

عندما تركز على الأهداف

1. **الأهداف المضمنة** - يتم تضمين الأهداف المطابقة لاستعلامك في المشروع الذي تم
   إنشاؤه
2. **التبعيات** - يتم تضمين جميع تبعيات الأهداف المركزة تلقائيًا
3. **أهداف الاختبار** - تم تضمين أهداف الاختبار للأهداف المركزة
4. **الاستبعاد** - يتم استبعاد جميع الأهداف الأخرى من مساحة العمل

هذا يعني أنك ستحصل على مساحة عمل أصغر حجمًا وأكثر قابلية للإدارة وتحتوي فقط على
ما تحتاجه للعمل على ميزتك.

## اصطلاحات تسمية العلامات {#tag-naming-conventions}

بينما يمكنك استخدام أي سلسلة كعلامة، فإن اتباع اصطلاح تسمية متسق يساعدك في
الحفاظ على تنظيم علاماتك:

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

استخدام البادئات مثل `ميزة:` أو `فريق:` أو `طبقة:` يجعل من السهل فهم الغرض من كل
علامة وتجنب تعارض التسمية.

## استخدام العلامات مع مساعدي وصف المشروع {#using-tags-with-helpers}

يمكنك الاستفادة من <LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف المشروع</LocalizedLink> لتوحيد كيفية تطبيق العلامات عبر مشروعك:

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

ثم استخدمها في قوائمك:

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

يمكنك من خلال التركيز على أجزاء محددة من مشروعك:

- **تصغير حجم مشروع Xcode** - العمل مع مشاريع أصغر حجماً وأسرع في الفتح والتنقل
- **تسريع عمليات الإنشاء** - أنشئ فقط ما تحتاجه لعملك الحالي
- **تحسين التركيز** - تجنب تشتيت الانتباه من التعليمات البرمجية غير ذات الصلة
- **تحسين الفهرسة** - يقوم Xcode بفهرسة كود أقل، مما يجعل الإكمال التلقائي أسرع

### تنظيم أفضل للمشروع

توفر العلامات طريقة مرنة لتنظيم قاعدة التعليمات البرمجية الخاصة بك:

- **أبعاد متعددة** - وضع علامات على الأهداف حسب الميزة أو الفريق أو الطبقة أو
  المنصة أو أي بُعد آخر
- **لا توجد تغييرات هيكلية** - إضافة هيكل تنظيمي دون تغيير تخطيط الدليل
- **الشواغل الشاملة** - يمكن أن ينتمي الهدف الواحد إلى عدة مجموعات منطقية

### التكامل مع التخزين المؤقت

تعمل علامات البيانات الوصفية بسلاسة مع <LocalizedLink href="/guides/features/cache">ميزات التخزين المؤقت في Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## أفضل الممارسات {#best-practices}

1. **ابدأ ببساطة** - ابدأ ببعد وسم واحد (على سبيل المثال، الميزات) وتوسع حسب
   الحاجة
2. **كن متناسقًا** - استخدم نفس اصطلاحات التسمية في جميع بياناتك
3. **قم بتوثيق علاماتك** - احتفظ بقائمة بالعلامات المتاحة ومعانيها في وثائق
   مشروعك
4. **استخدام المساعدين** - الاستفادة من مساعدي وصف المشروع لتوحيد تطبيق العلامات
5. **المراجعة الدورية** - مع تطور مشروعك، قم بمراجعة وتحديث استراتيجية وضع
   العلامات الخاصة بك بشكل دوري

## الميزات ذات الصلة {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">مشاركة الرمز</LocalizedLink> - استخدام مساعدي وصف المشروع لتوحيد استخدام العلامات
- <LocalizedLink href="/guides/features/cache">ذاكرة التخزين المؤقت</LocalizedLink> - ادمج العلامات مع التخزين المؤقت للحصول على أداء بناء مثالي
- <LocalizedLink href="/guides/features/selective-testing">اختبار انتقائي</LocalizedLink> - إجراء اختبارات للأهداف المتغيرة فقط
