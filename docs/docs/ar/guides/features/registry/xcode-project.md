---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# مشروع Xcode {#xcode-project}

لإضافة حزم باستخدام السجل في مشروع Xcode الخاص بك، استخدم واجهة المستخدم
الافتراضية لـ Xcode. يمكنك البحث عن الحزم في السجل بالنقر فوق الزر " `" + "` "
في علامة التبويب " `" "Package Dependencies" "` " في Xcode. إذا كانت الحزمة
متوفرة في السجل، فسترى " `" tuist.dev` registry في أعلى اليمين:

![إضافة تبعيات
الحزمة](/images/guides/features/build/registry/registry-add-package.png)

:::: المعلومات
<!-- -->
لا يدعم Xcode حاليًا الاستبدال التلقائي لحزم التحكم في المصدر بما يعادلها في
السجل. ستحتاج إلى إزالة حزمة التحكم في المصدر يدويًا وإضافة حزمة السجل لتسريع
عملية الحل.
<!-- -->
:::
