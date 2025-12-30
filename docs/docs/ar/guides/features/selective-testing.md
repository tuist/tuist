---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# الاختبار الانتقائي {#selective-testing}

مع نمو مشروعك، تزداد كمية الاختبارات الخاصة بك. لوقت طويل، يستغرق تشغيل جميع
الاختبارات على كل العلاقات العامة أو الدفع إلى `الرئيسي` عشرات الثواني. لكن هذا
الحل لا يتسع لآلاف الاختبارات التي قد يمتلكها فريقك.

في كل اختبار يتم تشغيله على CI، من المرجح أن تعيد تشغيل جميع الاختبارات، بغض
النظر عن التغييرات. يساعدك اختبار تويست الانتقائي على تسريع تشغيل الاختبارات نفسها بشكل كبير من خلال تشغيل الاختبارات التي تغيرت فقط منذ آخر تشغيل اختبار ناجح استنادًا إلى خوارزمية <LocalizedLink href="/guides/features/projects/hashing">التجزئة</LocalizedLink> الخاصة بنا.

يعمل الاختبار الانتقائي مع `xcodebuild` ، الذي يدعم أي مشروع Xcode، أو إذا كنت تنشئ مشاريعك باستخدام Tuist، يمكنك استخدام الأمر `tuist test` بدلاً من ذلك الذي يوفر بعض الراحة الإضافية مثل التكامل مع ذاكرة التخزين المؤقت الثنائية <LocalizedLink href="/guides/features/cache">الثنائية</LocalizedLink>. للبدء في الاختبار الانتقائي، اتبع التعليمات بناءً على إعداد مشروعك:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">إكس كودبيلد</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">المشروع المُنشأ</LocalizedLink>

::: warning وحدة نمطية مقابل مستوى الملف
نظرًا لاستحالة اكتشاف التبعيات داخل التعليمات البرمجية بين الاختبارات والمصادر،
فإن الحد الأقصى من دقة الاختبار الانتقائي يكون على مستوى الهدف. لذلك، نوصي
بإبقاء أهدافك صغيرة ومركزة لتحقيق أقصى قدر من فوائد الاختبار الانتقائي.
:::

::: warning تغطية الاختبار
تفترض أدوات تغطية الاختبار أن مجموعة الاختبار بأكملها تعمل مرة واحدة، مما يجعلها
غير متوافقة مع عمليات تشغيل الاختبار الانتقائية - وهذا يعني أن بيانات التغطية قد
لا تعكس الواقع عند استخدام اختيار الاختبار. هذا قيد معروف، وهذا لا يعني أنك تقوم
بأي شيء خاطئ. نحن نشجع الفرق على التفكير فيما إذا كانت التغطية لا تزال تجلب رؤى
مفيدة في هذا السياق، وإذا كانت كذلك، فكن مطمئنًا أننا نفكر بالفعل في كيفية جعل
التغطية تعمل بشكل صحيح مع عمليات التشغيل الانتقائية في المستقبل.
:::


## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

::: warning التكامل مع منصة GIT مطلوب
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج مشروعك <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink> مع منصة <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.
:::

بمجرد اتصال مشروع Tuist الخاص بك مع منصة Git الخاصة بك مثل [GitHub]
(https://github.com)، وبدء استخدام `tuist xcodebuild test` أو `tuist test` كجزء
من سير عمل CI wortkflow الخاص بك، سوف ينشر Tuist تعليقًا مباشرة في طلبات
السحب/الدمج الخاصة بك، بما في ذلك الاختبارات التي تم تشغيلها وأيها تم تخطيها:
![تعليق تطبيق GitHub مع رابط معاينة Tuist]
(/images/guides/features/selective-testing/github-app-comment.png)
