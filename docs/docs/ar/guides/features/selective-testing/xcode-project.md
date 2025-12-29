---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# مشروع Xcode {#xcode-project}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع تويست</LocalizedLink>
<!-- -->
:::

يمكنك تشغيل اختبارات مشاريع Xcode الخاصة بك بشكل انتقائي من خلال سطر الأوامر.
`لذلك، يمكنك إضافة الأمر` إلى الأمر `tuist` - على سبيل المثال، `tuist xcodebuild
test -scheme App`. يقوم الأمر بتجزئة مشروعك وعند النجاح، يستمر التجزئة لتحديد ما
تغير في عمليات التشغيل المستقبلية.

في عمليات التشغيل المستقبلية `tuist اختبار xcodebuild` يستخدم التجزئة بشفافية
لتصفية الاختبارات لتشغيل الاختبارات التي تغيرت فقط منذ آخر تشغيل اختبار ناجح.

على سبيل المثال، بافتراض الرسم البياني التالي للتبعية:

- `الميزة A` لديها اختبارات `FeatureATests` ، وتعتمد على `الأساسية`
- `الميزة ب` لديه اختبارات `FeatureBTests` ، ويعتمد على `الأساسية`
- `يحتوي الموقع الأساسي` على اختبارات `CoreTests CoreTests`

`سوف يتصرف tuist xcodebuild test` على هذا النحو:

| الإجراء                         | الوصف                                                                     | الحالة الداخلية                                                                     |
| ------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `tuist xcodebuild test` استدعاء | يقوم بتشغيل الاختبارات في `CoreTests` و `FeatureATests` و `FeatureBTests` | يتم الاحتفاظ بتجزئة `ميزات الاختبارات` و `ميزات الاختبارات` و `الاختبارات الأساسية` |
| `الميزة يتم تحديث`              | يقوم المطور بتعديل الكود البرمجي للهدف                                    | كما في السابق                                                                       |
| `tuist xcodebuild test` استدعاء | يقوم بتشغيل الاختبارات في `FeatureATests` لأنه تم تغيير التجزئة           | يتم استمرار التجزئة الجديدة لـ `FeatureATests`                                      |
| `تم تحديث الموقع الأساسي`       | يقوم المطور بتعديل الكود البرمجي للهدف                                    | كما في السابق                                                                       |
| `tuist xcodebuild test` استدعاء | يقوم بتشغيل الاختبارات في `CoreTests` و `FeatureATests` و `FeatureBTests` | التجزئة الجديدة لـ `FeatureATests` `FeatureBTests` ، و `CoreTests` يتم استمرارها    |

لاستخدام `tuist xcodebuild test` على CI الخاص بك، اتبع التعليمات الواردة في دليل <LocalizedLink href="/guides/integrations/continuous-integration">التكامل المستمر</LocalizedLink>.

شاهد الفيديو التالي لمشاهدة الاختبار الانتقائي أثناء العمل:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
