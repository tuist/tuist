---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# الاختبار الانتقائي {#الاختبار الانتقائي}

:::: متطلبات التحذير
<!-- -->
- مشروع <LocalizedLink href="/guides/features/projects">تم
  إنشاؤه</LocalizedLink>
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
<!-- -->
:::

لتشغيل الاختبارات بشكل انتقائي مع مشروعك الذي تم إنشاؤه، استخدم الأمر `tuist
test`. يقوم الأمر
<LocalizedLink href="/guides/features/projects/hashing">بتجزئة</LocalizedLink>
مشروع Xcode الخاص بك بنفس الطريقة التي يقوم بها
<LocalizedLink href="/guides/features/cache#cache-warming">بتسخين ذاكرة التخزين
المؤقت</LocalizedLink>، وعند النجاح، يستمر في التجزئة لتحديد ما تغير في
التشغيلات المستقبلية.

في عمليات التشغيل المستقبلية `tuist test` يستخدم بشكل شفاف علامات التجزئة لتصفية
الاختبارات لتشغيل فقط تلك التي تغيرت منذ آخر عملية تشغيل ناجحة للاختبار.

على سبيل المثال، بافتراض وجود الرسم البياني التالي للتبعية:

- `ميزة` يحتوي على اختبارات `ميزةATests` ، ويعتمد على `Core`
- `الميزة B` تحتوي على اختبارات `الميزة B الاختبارات` ، وتعتمد على `Core`
- `يحتوي Core` على اختبارات `CoreTests`

`اختبار tuist` سيتصرف على النحو التالي:

| الإجراء                | الوصف                                                                     | الحالة الداخلية                                                                        |
| ---------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `اختبار tuist استدعاء` | قم بتشغيل الاختبارات في `CoreTests` ، `FeatureATests` ، و `FeatureBTests` | يتم الاحتفاظ بعلامات التجزئة الخاصة بـ `FeatureATests` و `FeatureBTests` و `CoreTests` |
| `ميزة تم تحديث`        | يقوم المطور بتعديل كود الهدف                                              | كما في السابق                                                                          |
| `اختبار tuist استدعاء` | تشغيل الاختبارات في `FeatureATests` لأن التجزئة قد تغيرت                  | يتم الاحتفاظ بالهاش الجديد لـ `FeatureATests`                                          |
| `تم تحديث Core`        | يقوم المطور بتعديل كود الهدف                                              | كما في السابق                                                                          |
| `اختبار tuist استدعاء` | قم بتشغيل الاختبارات في `CoreTests` ، `FeatureATests` ، و `FeatureBTests` | يتم الاحتفاظ بالهاش الجديد لـ `FeatureATests` `FeatureBTests` و `CoreTests`            |

`اختبار tuist يتكامل` مباشرة مع التخزين المؤقت الثنائي لاستخدام أكبر عدد ممكن من
الملفات الثنائية من التخزين المحلي أو البعيد لتحسين وقت الإنشاء عند تشغيل مجموعة
الاختبارات. يمكن أن يؤدي الجمع بين الاختبار الانتقائي والتخزين المؤقت الثنائي
إلى تقليل الوقت الذي يستغرقه تشغيل الاختبارات على CI بشكل كبير.

## اختبارات واجهة المستخدم {#ui-tests}

يدعم Tuist الاختبار الانتقائي لاختبارات واجهة المستخدم. ومع ذلك، يحتاج Tuist إلى
معرفة الوجهة مسبقًا. فقط إذا قمت بتحديد الوجهة `` ، فسيقوم Tuist بتشغيل اختبارات
واجهة المستخدم بشكل انتقائي، مثل:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
