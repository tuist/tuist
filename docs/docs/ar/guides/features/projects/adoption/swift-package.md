---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# استخدام تويست مع حزمة سويفت <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

يدعم Tuist استخدام `Package.swift` كلغة برمجة خاصة لمشاريعك، ويقوم بتحويل أهداف
الحزمة إلى مشروع Xcode أصلي وأهداف.

:::: تحذير
<!-- -->
الهدف من هذه الميزة هو توفير طريقة سهلة للمطورين لتقييم تأثير اعتماد Tuist في
حزم Swift الخاصة بهم. لذلك، لا نخطط لدعم مجموعة كاملة من ميزات Swift Package
Manager ولا لإدخال كل ميزات Tuist الفريدة مثل
<LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف
المشروع</LocalizedLink> إلى عالم الحزم.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
تتوقع أوامر Tuist بنية دليل معينة
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">directory
structure</LocalizedLink> يتم تحديد جذرها بواسطة دليل `Tuist` أو دليل `.git`.
<!-- -->
:::

## استخدام تويست مع حزمة سويفت {#using-tuist-with-a-swift-package}

سنستخدم Tuist مع مستودع [TootSDK Package](https://github.com/TootSDK/TootSDK)،
الذي يحتوي على حزمة Swift. أول شيء علينا فعله هو استنساخ المستودع:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

بمجرد الوصول إلى دليل المستودع، نحتاج إلى تثبيت تبعيات Swift Package Manager:

```bash
tuist install
```

في الخلفية `tuist install` يستخدم Swift Package Manager لحل وسحب تبعيات الحزمة.
بعد اكتمال الحل، يمكنك إنشاء المشروع:

```bash
tuist generate
```

ها أنت ذا! لديك الآن مشروع Xcode أصلي يمكنك فتحه والبدء في العمل عليه.
