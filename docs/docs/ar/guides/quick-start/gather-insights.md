---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# اجمع الأفكار {#gather-insights}

يمكن لـ Tuist التكامل مع خادم لتوسيع قدراته. إحدى هذه القدرات هي جمع رؤى حول
مشروعك وبنياته. كل ما تحتاجه هو أن يكون لديك حساب مع مشروع في الخادم.

أولاً، ستحتاج إلى المصادقة عن طريق تشغيل:

```bash
tuist auth login
```

## إنشاء مشروع {#create-a-project}

يمكنك بعد ذلك إنشاء مشروع عن طريق تشغيل:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

انسخ `my-handle/MyApp` ، الذي يمثل المعرف الكامل للمشروع.

## ربط المشاريع {#connect-projects}

بعد إنشاء المشروع على الخادم، سيتعين عليك توصيله بمشروعك المحلي. قم بتشغيل
`tuist edit` وقم بتحرير ملف `Tuist.swift` لتضمين المعرف الكامل للمشروع:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

ها أنت ذا! أنت الآن جاهز لجمع معلومات حول مشروعك وبنياتك. قم بتشغيل `tuist test`
لتشغيل الاختبارات وإرسال النتائج إلى الخادم.

:::: المعلومات
<!-- -->
يقوم Tuist بوضع النتائج في قائمة الانتظار محليًا ويحاول إرسالها دون حظر الأمر.
لذلك، قد لا يتم إرسالها فورًا بعد انتهاء الأمر. في CI، يتم إرسال النتائج على
الفور.
<!-- -->
:::


![صورة تظهر قائمة بالعمليات في الخادم](/images/guides/quick-start/runs.png)

يعد الحصول على بيانات من مشاريعك وبنياتك أمرًا بالغ الأهمية لاتخاذ قرارات
مستنيرة. ستواصل Tuist توسيع قدراتها، وستستفيد منها دون الحاجة إلى تغيير تكوين
مشروعك. رائع، أليس كذلك؟ 🪄
