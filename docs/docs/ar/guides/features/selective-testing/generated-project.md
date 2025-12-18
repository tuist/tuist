---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# المشروع المُنشأ {#المشروع المُنشأ}

:::: متطلبات التحذير
<!-- -->
- أ <LocalizedLink href="/guides/features/projects"> مشروع تم
  إنشاؤه</LocalizedLink>
- أ <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع تويست
  <LocalizedLink href="/guides/server/accounts-and-projects">تويست</LocalizedLink>
<!-- -->
:::

لتشغيل الاختبارات بشكل انتقائي مع مشروعك الذي تم إنشاؤه، استخدم الأمر `tuist
test`. يقوم الأمر <LocalizedLink href="/guides/features/projects/hashing">
بتجزئة </LocalizedLink> مشروع Xcode الخاص بك بنفس الطريقة التي يقوم بها
<LocalizedLink href="/guides/features/cache#cache-warming"> لتسخين ذاكرة التخزين
المؤقت </LocalizedLink>، وعند النجاح، فإنه يستمر في التجزئة لتحديد ما تغير في
عمليات التشغيل المستقبلية.

في عمليات التشغيل المستقبلية `اختبار تويست` يستخدم التجزئة بشفافية لتصفية
الاختبارات لتشغيل الاختبارات التي تغيرت فقط منذ آخر عملية تشغيل اختبار ناجحة.

على سبيل المثال، بافتراض الرسم البياني التالي للتبعية:

- `الميزة A` لديها اختبارات `FeatureATests` ، وتعتمد على `الأساسية`
- `الميزة ب` لديه اختبارات `FeatureBTests` ، ويعتمد على `الأساسية`
- `يحتوي الموقع الأساسي` على اختبارات `CoreTests CoreTests`

`سوف يتصرف اختبار تويست` على هذا النحو:

| الإجراء                   | الوصف                                                               | الحالة الداخلية                                                                     |
| ------------------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `tuist test` invocation   | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | يتم الاحتفاظ بتجزئة `ميزات الاختبارات` و `ميزات الاختبارات` و `الاختبارات الأساسية` |
| `الميزة يتم تحديث`        | The developer modifies the code of a target                         | Same as before                                                                      |
| `tuist test` invocation   | يقوم بتشغيل الاختبارات في `FeatureATests` لأنه تم تغيير التجزئة     | يتم استمرار التجزئة الجديدة لـ `FeatureATests`                                      |
| `تم تحديث الموقع الأساسي` | The developer modifies the code of a target                         | Same as before                                                                      |
| `tuist test` invocation   | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | التجزئة الجديدة لـ `FeatureATests` `FeatureBTests` ، و `CoreTests` يتم استمرارها    |

`يتكامل اختبار tuist test` مباشرةً مع التخزين المؤقت الثنائي لاستخدام أكبر عدد
ممكن من الثنائيات من وحدة التخزين المحلية أو البعيدة لتحسين وقت الإنشاء عند
تشغيل مجموعة الاختبارات الخاصة بك. يمكن للجمع بين الاختبار الانتقائي والتخزين
المؤقت الثنائي أن يقلل بشكل كبير من الوقت الذي يستغرقه تشغيل الاختبارات على CI
الخاص بك.

## اختبارات واجهة المستخدم {#ui-tests}

يدعم Tuist الاختبار الانتقائي لاختبارات واجهة المستخدم. ومع ذلك، يحتاج تويست إلى
معرفة الوجهة مسبقًا. فقط إذا قمت بتحديد الوجهة `الوجهة` المعلمة ، سيقوم تويست
بتشغيل اختبارات واجهة المستخدم بشكل انتقائي، مثل:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
