---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# استخدام تويست مع حزمة سويفت <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

يدعم تويست استخدام `Package.swift.swift` كـ DSL لمشاريعك ويحول أهداف الحزمة
الخاصة بك إلى مشروع Xcode أصلي وأهدافه.

::: warning
الهدف من هذه الميزة هو توفير طريقة سهلة للمطورين لتقييم تأثير اعتماد تويست في
حزم سويفت الخاصة بهم. لذلك، نحن لا نخطط لدعم المجموعة الكاملة لميزات مدير حزم
سويفت ولا لجلب كل ميزات تويست الفريدة مثل <LocalizedLink href="/guides/features/projects/code-sharing">مساعدات وصف المشروع</LocalizedLink> إلى عالم الحزم.
:::

::: info ROOT DIRECTORY
تتوقّع أوامر تويست بنية دليل <LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">دليل معيّن</LocalizedLink> يُعرّف جذره بدليل `تويست` أو `.git`.
:::

## استخدام تويست مع حزمة سويفت {#using-tuist-with-a-swift-package}

سوف نستخدم تويست مع مستودع [TootSDK Package]
(https://github.com/TootSDK/TootSDK) الذي يحتوي على حزمة سويفت. أول شيء نحتاج
إلى القيام به هو استنساخ المستودع:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

بمجرد الوصول إلى دليل المستودع، نحتاج إلى تثبيت تبعيات Swift Package Manager:

```bash
tuist install
```

تحت غطاء محرك السيارة `تويست تثبيت` يستخدم مدير حزم سويفت لحل وسحب تبعيات
الحزمة. بعد اكتمال الحل، يمكنك بعد ذلك إنشاء المشروع:

```bash
tuist generate
```

ها هو! لديك مشروع Xcode أصلي يمكنك فتحه وبدء العمل عليه.
