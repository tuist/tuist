---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# الاختبار الانتقائي {#الاختبار الانتقائي}

مع نمو مشروعك، تزداد كمية الاختبارات الخاصة بك. لوقت طويل، يستغرق تشغيل جميع
الاختبارات على كل العلاقات العامة أو الدفع إلى `الرئيسي` عشرات الثواني. لكن هذا
الحل لا يتسع لآلاف الاختبارات التي قد يمتلكها فريقك.

في كل اختبار يتم تشغيله على CI، من المرجح أن تعيد تشغيل جميع الاختبارات، بغض
النظر عن التغييرات. يساعدك اختبار تويست الانتقائي على تسريع تشغيل الاختبارات
نفسها بشكل كبير من خلال تشغيل الاختبارات التي تغيرت فقط منذ آخر تشغيل اختبار
ناجح استنادًا إلى خوارزمية
<LocalizedLink href="/guides/features/projects/hashing"> التجزئة</LocalizedLink>
الخاصة بنا.

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

:::: تحذير وحدة نمطية مقابل مستوى الملف
<!-- -->
نظرًا لاستحالة اكتشاف التبعيات داخل التعليمات البرمجية بين الاختبارات والمصادر،
فإن الحد الأقصى من دقة الاختبار الانتقائي يكون على مستوى الهدف. لذلك، نوصي
بإبقاء أهدافك صغيرة ومركزة لتحقيق أقصى قدر من فوائد الاختبار الانتقائي.
<!-- -->
:::

:::: تحذير تغطية الاختبار
<!-- -->
تفترض أدوات تغطية الاختبار أن مجموعة الاختبار بأكملها تعمل مرة واحدة، مما يجعلها
غير متوافقة مع عمليات تشغيل الاختبار الانتقائية - وهذا يعني أن بيانات التغطية قد
لا تعكس الواقع عند استخدام اختيار الاختبار. هذا قيد معروف، وهذا لا يعني أنك تقوم
بأي شيء خاطئ. نحن نشجع الفرق على التفكير فيما إذا كانت التغطية لا تزال تجلب رؤى
مفيدة في هذا السياق، وإذا كانت كذلك، فكن مطمئنًا أننا نفكر بالفعل في كيفية جعل
التغطية تعمل بشكل صحيح مع عمليات التشغيل الانتقائية في المستقبل.
<!-- -->
:::


## تعليقات طلب السحب/الدمج {#pullmerge-request-comments}

:::: تحذير التكامل مع منصة GIT مطلوب
<!-- -->
للحصول على تعليقات طلبات السحب/الدمج التلقائية، ادمج مشروعك
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
مع <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>منصة
<LocalizedLink href="/guides/server/authentication">Git.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
