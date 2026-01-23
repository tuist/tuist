---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# تثبيت الاستضافة الذاتية {#self-host-installation}

نحن نقدم نسخة مستضافة ذاتيًا من خادم Tuist للمؤسسات التي تحتاج إلى مزيد من
التحكم في بنيتها التحتية. تتيح لك هذه النسخة استضافة Tuist على بنيتك التحتية
الخاصة، مما يضمن بقاء بياناتك آمنة وسرية.

::: warning LICENSE REQUIRED
<!-- -->
يتطلب استضافة Tuist ذاتيًا ترخيصًا مدفوعًا صالحًا قانونيًا. الإصدار المحلي من
Tuist متاح فقط للمؤسسات التي تستخدم خطة Enterprise. إذا كنت مهتمًا بهذا الإصدار،
يرجى التواصل مع [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

## إيقاع الإصدار {#release-cadence}

نصدر إصدارات جديدة من Tuist باستمرار مع ظهور تغييرات جديدة قابلة للإصدار على
النسخة الرئيسية. نتبع [الترقيم الدلالي](https://semver.org/) لضمان ترقيم وتوافق
يمكن التنبؤ بهما.

يُستخدم المكون الرئيسي للإشارة إلى التغييرات الجذرية في خادم Tuist التي تتطلب
التنسيق مع المستخدمين المحليين. لا تتوقع منا استخدامه، وفي حالة احتياجنا إليه،
كن مطمئنًا أننا سنعمل معك على إجراء الانتقال بسلاسة.

## النشر المستمر {#continuous-deployment}

نوصي بشدة بإعداد خط أنابيب نشر مستمر يقوم تلقائيًا بنشر أحدث إصدار من Tuist كل
يوم. يضمن ذلك حصولك دائمًا على أحدث الميزات والتحسينات والتحديثات الأمنية.

فيما يلي مثال على سير عمل GitHub Actions الذي يتحقق من الإصدارات الجديدة وينشرها
يوميًا:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## متطلبات وقت التشغيل {#runtime-requirements}

يوضح هذا القسم متطلبات استضافة خادم Tuist على البنية التحتية الخاصة بك.

### مصفوفة التوافق {#compatibility-matrix}

تم اختبار خادم Tuist وهو متوافق مع الإصدارات الدنيا التالية:

| المكون      | الإصدار الأدنى | ملاحظات                        |
| ----------- | -------------- | ------------------------------ |
| PostgreSQL  | 15             | مع ملحق TimescaleDB            |
| TimescaleDB | 2.16.1         | ملحق PostgreSQL المطلوب (مهمل) |
| ClickHouse  | 25             | مطلوب للتحليلات                |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB هو حاليًا امتداد PostgreSQL مطلوب لخادم Tuist، ويستخدم لتخزين
البيانات الزمنية والاستعلام عنها. ومع ذلك، **TimescaleDB أصبح قديمًا** وسيتم
حذفه كاعتماد مطلوب في المستقبل القريب حيث نقوم بترحيل جميع وظائف البيانات
الزمنية إلى ClickHouse. في الوقت الحالي، تأكد من أن مثيل PostgreSQL الخاص بك
يحتوي على TimescaleDB مثبتًا وممكّنًا.
<!-- -->
:::

### تشغيل الصور الافتراضية Docker {#running-dockervirtualized-images}

نقوم بتوزيع الخادم كصورة [Docker](https://www.docker.com/) عبر [سجل حاويات
GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

لتشغيله، يجب أن تدعم البنية التحتية الخاصة بك تشغيل صور Docker. لاحظ أن معظم
مزودي البنية التحتية يدعمونه لأنه أصبح الحاوية القياسية لتوزيع البرامج وتشغيلها
في بيئات الإنتاج.

### قاعدة بيانات Postgres {#postgres-database}

بالإضافة إلى تشغيل صور Docker، ستحتاج إلى [قاعدة بيانات
Postgres](https://www.postgresql.org/) مع [ملحق
TimescaleDB](https://www.timescale.com/) لتخزين البيانات العلائقية والسلسلة
الزمنية. تضم معظم مزودي البنية التحتية قواعد بيانات Postgres في عروضهم (على سبيل
المثال، [AWS](https://aws.amazon.com/rds/postgresql/) و[Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**ملحق TimescaleDB مطلوب:** يتطلب Tuist ملحق TimescaleDB لتخزين واستعلام بيانات
السلاسل الزمنية بكفاءة. يستخدم هذا الملحق لأحداث الأوامر والتحليلات والميزات
الأخرى القائمة على الوقت. تأكد من تثبيت TimescaleDB وتمكينه في مثيل PostgreSQL
الخاص بك قبل تشغيل Tuist.

::: info MIGRATIONS
<!-- -->
تقوم نقطة الدخول لصورة Docker بتشغيل أي عمليات ترحيل مخطط معلقة تلقائيًا قبل بدء
الخدمة. إذا فشلت عمليات الترحيل بسبب امتداد TimescaleDB مفقود، فستحتاج إلى
تثبيته في قاعدة البيانات أولاً.
<!-- -->
:::

### قاعدة بيانات ClickHouse {#clickhouse-database}

تستخدم Tuist [ClickHouse](https://clickhouse.com/) لتخزين واستعلام كميات كبيرة
من بيانات التحليلات. ClickHouse هو **مطلوب** لميزات مثل بناء الرؤى وسيكون قاعدة
البيانات الزمنية الأساسية مع تخلصنا تدريجياً من TimescaleDB. يمكنك اختيار ما إذا
كنت تريد استضافة ClickHouse بنفسك أو استخدام خدمتهم المستضافة.

::: info MIGRATIONS
<!-- -->
تقوم نقطة الدخول لصورة Docker بتشغيل أي عمليات ترحيل مخطط ClickHouse معلقة
تلقائيًا قبل بدء الخدمة.
<!-- -->
:::

### التخزين {#storage}

ستحتاج أيضًا إلى حل لتخزين الملفات (مثل ملفات الإطار والمكتبة الثنائية). ندعم
حاليًا أي تخزين متوافق مع S3.

::: tip OPTIMIZED CACHING
<!-- -->
إذا كان هدفك الأساسي هو إحضار سلة خاصة بك لتخزين الملفات الثنائية وتقليل زمن
انتقال ذاكرة التخزين المؤقت، فقد لا تحتاج إلى استضافة الخادم بالكامل بنفسك.
يمكنك استضافة عقد ذاكرة التخزين المؤقت بنفسك وربطها بخادم Tuist المستضاف أو
بخادمك المستضاف بنفسك.

انظر <LocalizedLink href="/guides/cache/self-host">دليل الاستضافة الذاتية
للذاكرة المؤقتة</LocalizedLink>.
<!-- -->
:::

## التكوين {#التكوين}

يتم تكوين الخدمة في وقت التشغيل من خلال متغيرات البيئة. نظرًا للطبيعة الحساسة
لهذه المتغيرات، ننصح بتشفيرها وتخزينها في حلول آمنة لإدارة كلمات المرور. كن
مطمئنًا، تتعامل Tuist مع هذه المتغيرات بعناية فائقة، وتضمن عدم عرضها في السجلات.

::: info LAUNCH CHECKS
<!-- -->
يتم التحقق من المتغيرات الضرورية عند بدء التشغيل. إذا كان هناك أي متغيرات
مفقودة، فسيفشل التشغيل وستظهر رسالة خطأ توضح المتغيرات المفقودة.
<!-- -->
:::

### تكوين الترخيص {#license-configuration}

بصفتك مستخدمًا محليًا، ستتلقى مفتاح ترخيص يجب عليك عرضه كمتغير بيئة. يُستخدم هذا
المفتاح للتحقق من صحة الترخيص والتأكد من أن الخدمة تعمل وفقًا لشروط الاتفاقية.

| متغير البيئة                       | الوصف                                                                                                                                                                                                                                          | مطلوب | افتراضي | مثال على ذلك                              |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | ------- | ----------------------------------------- |
| `TUIST_LICENSE`                    | الترخيص المقدم بعد توقيع اتفاقية مستوى الخدمة                                                                                                                                                                                                  | نعم*  |         | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **بديل استثنائي لـ `TUIST_LICENSE`**. شهادة عامة مشفرة بـ Base64 للتحقق من صحة الترخيص في وضع عدم الاتصال بالإنترنت في البيئات المعزولة التي لا يستطيع فيها الخادم الاتصال بالخدمات الخارجية. استخدم فقط عندما لا يمكن استخدام `TUIST_LICENSE` | نعم*  |         | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* يجب توفير إما `TUIST_LICENSE` أو `TUIST_LICENSE_CERTIFICATE_BASE64` ، ولكن
ليس كلاهما. استخدم `TUIST_LICENSE` للنشر القياسي.

::: warning EXPIRATION DATE
<!-- -->
التراخيص لها تاريخ انتهاء صلاحية. سيتلقى المستخدمون تحذيرًا أثناء استخدام أوامر
Tuist التي تتفاعل مع الخادم إذا انتهت صلاحية الترخيص في أقل من 30 يومًا. إذا كنت
مهتمًا بتجديد ترخيصك، فيرجى التواصل مع
[contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

### تكوين بيئة الأساس {#base-environment-configuration}

| متغير البيئة                          | الوصف                                                                                                                                                                 | مطلوب | افتراضي                            | مثال على ذلك                                                                |                                                                                                                                    |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | ---------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | عنوان URL الأساسي للوصول إلى المثيل من الإنترنت                                                                                                                       | نعم   |                                    | https://tuist.dev                                                           |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | المفتاح المستخدم لتشفير المعلومات (مثل الجلسات في ملف تعريف الارتباط)                                                                                                 | نعم   |                                    |                                                                             | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper لتوليد كلمات مرور مجزأة                                                                                                                                        | لا    | `$TUIST_SECRET_KEY_BASE`           |                                                                             |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | مفتاح سري لإنشاء رموز عشوائية                                                                                                                                         | لا    | `$TUIST_SECRET_KEY_BASE`           |                                                                             |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | مفتاح 32 بايت لتشفير البيانات الحساسة باستخدام AES-GCM                                                                                                                | لا    | `$TUIST_SECRET_KEY_BASE`           |                                                                             |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | عندما `1` فإنه يقوم بتكوين التطبيق لاستخدام عناوين IPv6                                                                                                               | لا    | `0`                                | `1`                                                                         |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | مستوى السجل الذي سيتم استخدامه للتطبيق                                                                                                                                | لا    | `معلومات`                          | [مستويات السجل](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | نسخة URL لاسم تطبيق GitHub الخاص بك                                                                                                                                   | لا    |                                    | `my-app`                                                                    |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | المفتاح الخاص المشفر بـ base64 المستخدم في تطبيق GitHub لفتح وظائف إضافية مثل نشر تعليقات PR تلقائية                                                                  | لا    | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                             |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | المفتاح الخاص المستخدم لتطبيق GitHub لفتح وظائف إضافية مثل نشر تعليقات PR تلقائية. **نوصي باستخدام الإصدار المشفر بـ base64 بدلاً من ذلك لتجنب مشاكل الأحرف الخاصة.** | لا    | `-----BEGIN RSA...`                |                                                                             |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | قائمة مفصولة بفواصل بأسماء المستخدمين الذين لديهم حق الوصول إلى عناوين URL للعمليات                                                                                   | لا    |                                    | `user1,user2`                                                               |                                                                                                                                    |
| `TUIST_WEB`                           | قم بتمكين نقطة نهاية خادم الويب                                                                                                                                       | لا    | `1`                                | `1` أو `0`                                                                  |                                                                                                                                    |

### تكوين قاعدة البيانات {#database-configuration}

تُستخدم المتغيرات البيئية التالية لتكوين اتصال قاعدة البيانات:

| متغير البيئة                         | الوصف                                                                                                                                                                                                                                       | مطلوب | افتراضي   | مثال على ذلك                                                           |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | عنوان URL للوصول إلى قاعدة بيانات Postgres. لاحظ أن عنوان URL يجب أن يحتوي على معلومات المصادقة                                                                                                                                             | نعم   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | عنوان URL للوصول إلى قاعدة بيانات ClickHouse. لاحظ أن عنوان URL يجب أن يحتوي على معلومات المصادقة                                                                                                                                           | لا    |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | عندما يكون صحيحًا، يستخدم [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) للاتصال بقاعدة البيانات                                                                                                                             | لا    | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | عدد الاتصالات التي يجب إبقاؤها مفتوحة في مجموعة الاتصالات                                                                                                                                                                                   | لا    | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | الفاصل الزمني (بالمللي ثانية) للتحقق مما إذا كانت جميع الاتصالات التي تم سحبها من المجموعة قد استغرقت أكثر من فاصل الزمن الخاص بالطابور [(مزيد من المعلومات)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | لا    | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | الحد الزمني (بالميلي ثانية) في قائمة الانتظار الذي يستخدمه المجمع لتحديد ما إذا كان يجب البدء في إسقاط الاتصالات الجديدة [(مزيد من المعلومات)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)                | لا    | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | الفاصل الزمني بالمللي ثانية بين عمليات مسح ذاكرة التخزين المؤقتة لـ ClickHouse                                                                                                                                                              | لا    | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | الحجم الأقصى لمخزن ClickHouse المؤقت بالبايت قبل فرض عملية مسح                                                                                                                                                                              | لا    | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | عدد عمليات التخزين المؤقت لـ ClickHouse المطلوب تشغيلها                                                                                                                                                                                     | لا    | `5`       | `5`                                                                    |

### تكوين بيئة المصادقة {#authentication-environment-configuration}

نحن نسهل المصادقة من خلال [مزودي الهوية
(IdP)](https://en.wikipedia.org/wiki/Identity_provider). للاستفادة من ذلك، تأكد
من وجود جميع متغيرات البيئة الضرورية للمزود المختار في بيئة الخادم. **سيؤدي
فقدان المتغيرات** إلى تجاوز Tuist لهذا المزود.

#### GitHub {#github}

نوصي بالمصادقة باستخدام [تطبيق
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)،
ولكن يمكنك أيضًا استخدام [تطبيق
OAuth](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app).
تأكد من تضمين جميع متغيرات البيئة الأساسية المحددة بواسطة GitHub في بيئة الخادم.
سيؤدي غياب المتغيرات إلى تجاهل Tuist لمصادقة GitHub. لإعداد تطبيق GitHub بشكل
صحيح:
- في الإعدادات العامة لتطبيق GitHub:
    - انسخ معرف عميل `` وقم بتعيينه على النحو التالي:
      `TUIST_GITHUB_APP_CLIENT_ID`
    - قم بإنشاء ونسخ سر عميل جديد لـ `` وقم بتعيينه على أنه
      `TUIST_GITHUB_APP_CLIENT_SECRET`
    - اضبط عنوان URL للرد على `` على
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` يمكن أن
      يكون أيضًا عنوان IP لخادمك.
- الأذونات التالية مطلوبة:
  - المستودعات:
    - طلبات السحب: القراءة والكتابة
  - الحسابات:
    - عناوين البريد الإلكتروني: للقراءة فقط

`في قسم "أذونات وأحداث"`" `" "أذونات الحساب"` " `" "عناوين البريد الإلكتروني"`
"أذونات" `"قراءة فقط"`.

ستحتاج بعد ذلك إلى عرض متغيرات البيئة التالية في البيئة التي يعمل فيها خادم
Tuist:

| متغير البيئة                     | الوصف                     | مطلوب | افتراضي | مثال على ذلك                               |
| -------------------------------- | ------------------------- | ----- | ------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | معرف العميل لتطبيق GitHub | نعم   |         | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | سر العميل للتطبيق         | نعم   |         | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### جوجل {#google}

يمكنك إعداد المصادقة مع Google باستخدام [OAuth
2](https://developers.google.com/identity/protocols/oauth2). للقيام بذلك، ستحتاج
إلى إنشاء بيانات اعتماد جديدة من نوع معرف عميل OAuth. عند إنشاء بيانات الاعتماد،
حدد "تطبيق ويب" كنوع التطبيق، وقم بتسميته `Tuist` ، وقم بتعيين عنوان URI لإعادة
التوجيه إلى `{base_url}/users/auth/google/callback` حيث `base_url` هو عنوان URL
الذي تعمل عليه خدمتك المستضافة. بمجرد إنشاء التطبيق، انسخ معرف العميل والسر وقم
بتعيينهما كمتغيرات بيئة `GOOGLE_CLIENT_ID` و `GOOGLE_CLIENT_SECRET` على التوالي.

::: info CONSENT SCREEN SCOPES
<!-- -->
قد تحتاج إلى إنشاء شاشة موافقة. عند القيام بذلك، تأكد من إضافة نطاقات
`userinfo.email` و `openid` وقم بتمييز التطبيق على أنه داخلي.
<!-- -->
:::

#### Okta {#okta}

يمكنك تمكين المصادقة باستخدام Okta من خلال بروتوكول [OAuth
2.0](https://oauth.net/2/). سيتعين عليك [إنشاء
تطبيق](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
على Okta باتباع <LocalizedLink href="/guides/integrations/sso#okta">هذه
التعليمات</LocalizedLink>.

ستحتاج إلى تعيين متغيرات البيئة التالية بمجرد الحصول على معرف العميل والسر أثناء
إعداد تطبيق Okta:

| متغير البيئة                 | الوصف                                                           | مطلوب | افتراضي | مثال على ذلك |
| ---------------------------- | --------------------------------------------------------------- | ----- | ------- | ------------ |
| `TUIST_OKTA_1_CLIENT_ID`     | معرف العميل للمصادقة على Okta. يجب أن يكون الرقم هو معرف مؤسستك | نعم   |         |              |
| `TUIST_OKTA_1_CLIENT_SECRET` | سر العميل للمصادقة على Okta                                     | نعم   |         |              |

يجب استبدال الرقم `1` برقم معرف مؤسستك. عادةً ما يكون الرقم 1، ولكن تحقق من
قاعدة البيانات الخاصة بك.

### تكوين بيئة التخزين {#storage-environment-configuration}

يحتاج Tuist إلى مساحة تخزين لاستيعاب الملفات التي يتم تحميلها عبر واجهة برمجة
التطبيقات. من الضروري جدًا تكوين أحد حلول التخزين المدعومة** لكي يعمل Tuist
بفعالية. **

#### مخازن متوافقة مع S3 {#s3compliant-storages}

يمكنك استخدام أي مزود تخزين متوافق مع S3 لتخزين العناصر. المتغيرات البيئية
التالية مطلوبة للمصادقة وتكوين التكامل مع مزود التخزين:

| متغير البيئة                                            | الوصف                                                                                                                                  | مطلوب | افتراضي          | مثال على ذلك                                                  |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ----- | ---------------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` أو `AWS_ACCESS_KEY_ID`         | معرف مفتاح الوصول للمصادقة على مزود التخزين                                                                                            | نعم   |                  | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` أو `AWS_SECRET_ACCESS_KEY` | مفتاح الوصول السري للمصادقة على مزود التخزين                                                                                           | نعم   |                  | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` أو `AWS_REGION`                       | المنطقة التي يقع فيها الدلو                                                                                                            | لا    | `تلقائي`         | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` أو `AWS_ENDPOINT`                   | نقطة النهاية لمزود التخزين                                                                                                             | نعم   |                  | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                  | اسم الحاوية التي سيتم تخزين القطع الأثرية فيها                                                                                         | نعم   |                  | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                  | شهادة CA مشفرة بـ PEM للتحقق من اتصالات S3 HTTPS. مفيدة للبيئات المعزولة التي تستخدم شهادات موقعة ذاتيًا أو سلطات إصدار شهادات داخلية. | لا    | حزمة نظام CA     | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                              | مدة الانتظار (بالمللي ثانية) لإنشاء اتصال بمزود التخزين                                                                                | لا    | `3000`           | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                              | مدة الانتظار (بالمللي ثانية) لاستلام البيانات من مزود التخزين                                                                          | لا    | `5000`           | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                 | مدة الانتظار (بالمللي ثانية) لمجموعة الاتصالات بمزود التخزين. استخدم `infinity` لعدم وجود مدة انتظار                                   | لا    | `5000`           | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                           | الحد الأقصى لوقت الخمول (بالمللي ثانية) للاتصالات في المجموعة. استخدم `infinity` للحفاظ على الاتصالات نشطة إلى أجل غير مسمى.           | لا    | `infinity`       | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                    | الحد الأقصى لعدد الاتصالات لكل تجمع                                                                                                    | لا    | `500`            | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                   | عدد مجموعات الاتصال المطلوب استخدامها                                                                                                  | لا    | عدد مخططي النظام | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                     | البروتوكول الذي يجب استخدامه عند الاتصال بمزود التخزين (`http1` أو `http2`)                                                            | لا    | `http1`          | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                 | ما إذا كان يجب إنشاء عنوان URL باستخدام اسم المجموعة كنطاق فرعي (مضيف افتراضي)                                                         | لا    | `false`          | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
إذا كان مزود التخزين الخاص بك هو AWS وترغب في المصادقة باستخدام رمز هوية الويب،
يمكنك تعيين متغير البيئة `TUIST_S3_AUTHENTICATION_METHOD` إلى
`aws_web_identity_token_from_env_vars` ، وستستخدم Tuist هذه الطريقة باستخدام
متغيرات بيئة AWS التقليدية.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
بالنسبة إلى Google Cloud Storage، اتبع [هذه
المستندات](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
للحصول على `AWS_ACCESS_KEY_ID` و `AWS_SECRET_ACCESS_KEY`. يجب تعيين
`AWS_ENDPOINT` إلى `https://storage.googleapis.com`. المتغيرات البيئية الأخرى هي
نفسها المستخدمة في أي تخزين آخر متوافق مع S3.

### تكوين البريد الإلكتروني {#email-configuration}

يتطلب Tuist وظيفة البريد الإلكتروني لمصادقة المستخدم وإشعارات المعاملات (مثل
إعادة تعيين كلمة المرور وإشعارات الحساب). حاليًا، **لا يدعم سوى Mailgun** كمزود
خدمة البريد الإلكتروني.

| متغير البيئة                     | الوصف                                                                                                                                      | مطلوب | افتراضي                                                                         | مثال على ذلك               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ----- | ------------------------------------------------------------------------------- | -------------------------- |
| `TUIST_MAILGUN_API_KEY`          | مفتاح API للمصادقة مع Mailgun                                                                                                              | نعم*  |                                                                                 | `key-1234567890abcdef`     |
| `TUIST_MAILING_DOMAIN`           | المجال الذي سيتم إرسال رسائل البريد الإلكتروني منه                                                                                         | نعم*  |                                                                                 | `mg.tuist.io`              |
| `TUIST_MAILING_FROM_ADDRESS`     | عنوان البريد الإلكتروني الذي سيظهر في حقل "من"                                                                                             | نعم*  |                                                                                 | `noreply@tuist.io`         |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | عنوان الرد الاختياري لردود المستخدمين                                                                                                      | لا    |                                                                                 | `support@tuist.dev`        |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | تخطي تأكيد البريد الإلكتروني لتسجيلات المستخدمين الجدد. عند التمكين، يتم تأكيد المستخدمين تلقائيًا ويمكنهم تسجيل الدخول فورًا بعد التسجيل. | لا    | `صحيح` إذا لم يتم تكوين البريد الإلكتروني، `خطأ` إذا تم تكوين البريد الإلكتروني | `صحيح` ، `خطأ` ، `1` ، `0` |

\* متغيرات تكوين البريد الإلكتروني مطلوبة فقط إذا كنت ترغب في إرسال رسائل بريد
إلكتروني. إذا لم يتم تكوينها، يتم تخطي تأكيد البريد الإلكتروني تلقائيًا.

::: info SMTP SUPPORT
<!-- -->
لا يتوفر دعم SMTP عام حاليًا. إذا كنت بحاجة إلى دعم SMTP لنشرك المحلي، فيرجى
التواصل مع [contact@tuist.dev](mailto:contact@tuist.dev) لمناقشة متطلباتك.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
بالنسبة للتثبيتات المحلية التي لا تتوفر فيها خدمة الإنترنت أو تكوين مزود البريد
الإلكتروني، يتم تخطي تأكيد البريد الإلكتروني تلقائيًا بشكل افتراضي. يمكن
للمستخدمين تسجيل الدخول فورًا بعد التسجيل. إذا كان البريد الإلكتروني مكونًا
ولكنك لا تزال ترغب في تخطي التأكيد، فاضبط `TUIST_SKIP_EMAIL_CONFIRMATION=true`.
لطلب تأكيد البريد الإلكتروني عند تكوين البريد الإلكتروني، اضبط
`TUIST_SKIP_EMAIL_CONFIRMATION=false`.
<!-- -->
:::

### تكوين منصة Git {#git-platform-configuration}

يمكن لـ Tuist <LocalizedLink href="/guides/server/authentication">التكامل مع
منصات Git</LocalizedLink> لتوفير ميزات إضافية مثل نشر التعليقات تلقائيًا في
طلبات السحب الخاصة بك.

#### GitHub {#platform-github}

ستحتاج إلى [إنشاء تطبيق
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
يمكنك إعادة استخدام التطبيق الذي أنشأته للمصادقة، ما لم تكن قد أنشأت تطبيق OAuth
GitHub. في قسم `أذونات وأحداث`'s `أذونات المستودع` ، ستحتاج إلى تعيين أذونات
`طلبات السحب` إلى `القراءة والكتابة`.

بالإضافة إلى `TUIST_GITHUB_APP_CLIENT_ID` و `TUIST_GITHUB_APP_CLIENT_SECRET` ،
ستحتاج إلى المتغيرات البيئية التالية:

| متغير البيئة                   | الوصف                       | مطلوب | افتراضي | مثال على ذلك                         |
| ------------------------------ | --------------------------- | ----- | ------- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | المفتاح الخاص لتطبيق GitHub | نعم   |         | `-----BEGIN RSA PRIVATE KEY-----...` |

## الاختبار محليًا {#testing-locally}

نحن نقدم تكوين Docker Compose شاملًا يتضمن جميع التبعيات المطلوبة لاختبار خادم
Tuist على جهازك المحلي قبل نشره على البنية التحتية الخاصة بك:

- PostgreSQL 15 مع امتداد TimescaleDB 2.16 (مهمل)
- ClickHouse 25 للتحليلات
- ClickHouse Keeper للتنسيق
- MinIO للتخزين المتوافق مع S3
- Redis لتخزين KV دائم عبر عمليات النشر (اختياري)
- pgweb لإدارة قواعد البيانات

::: danger LICENSE REQUIRED
<!-- -->
`صالح TUIST_LICENSE` متغير بيئة مطلوب قانونًا لتشغيل خادم Tuist، بما في ذلك
حالات التطوير المحلية. إذا كنت بحاجة إلى ترخيص، فيرجى التواصل مع
[contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

**البدء السريع:**

1. قم بتنزيل ملفات التكوين:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. تكوين متغيرات البيئة:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. ابدأ جميع الخدمات:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. قم بالوصول إلى الخادم على http://localhost:8080

**نقاط نهاية الخدمة:**
- خادم Tuist: http://localhost:8080
- MinIO Console: http://localhost:9003 (بيانات الاعتماد: `tuist` /
  `tuist_dev_password`)
- واجهة برمجة تطبيقات MinIO: http://localhost:9002
- pgweb (واجهة مستخدم PostgreSQL): http://localhost:8081
- مقاييس بروميثيوس: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**الأوامر الشائعة:**

تحقق من حالة الخدمة:
```bash
docker compose ps
# or: podman compose ps
```

عرض السجلات:
```bash
docker compose logs -f tuist
```

إيقاف الخدمات:
```bash
docker compose down
```

إعادة ضبط كل شيء (حذف جميع البيانات):
```bash
docker compose down -v
```

**ملفات التكوين:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - أكمل تكوين Docker
  Compose
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - تكوين
  ClickHouse
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - تكوين ClickHouse Keeper
- [.env.example](/server/self-host/.env.example) - ملف متغيرات البيئة النموذجي

## النشر {#deployment}

الصورة الرسمية لـ Tuist Docker متاحة على:
```
ghcr.io/tuist/tuist
```

### سحب صورة Docker {#pulling-the-docker-image}

يمكنك استرداد الصورة عن طريق تنفيذ الأمر التالي:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

أو اسحب نسخة محددة:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### نشر صورة Docker {#deploying-the-docker-image}

ستختلف عملية نشر صورة Docker بناءً على مزود الخدمة السحابية الذي اخترته ونهج
النشر المستمر الذي تتبعه مؤسستك. نظرًا لأن معظم الحلول والأدوات السحابية، مثل
[Kubernetes](https://kubernetes.io/)، تستخدم صور Docker كوحدات أساسية، فإن
الأمثلة الواردة في هذا القسم يجب أن تتوافق جيدًا مع الإعدادات الحالية لديك.

:::: تحذير
<!-- -->
إذا كان خط أنابيب النشر الخاص بك يحتاج إلى التحقق من أن الخادم يعمل، يمكنك إرسال
طلب HTTP `GET` إلى `/ready` والتأكد من رمز الحالة `200` في الاستجابة.
<!-- -->
:::

#### طيران {#fly}

لنشر التطبيق على [Fly](https://fly.io/)، ستحتاج إلى ملف تكوين `fly.toml`. ضع في
اعتبارك إنشاؤه ديناميكيًا داخل خط أنابيب النشر المستمر (CD). فيما يلي مثال مرجعي
لاستخدامك:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

ثم يمكنك تشغيل `fly launch --local-only --no-deploy` لتشغيل التطبيق. في عمليات
النشر اللاحقة، بدلاً من تشغيل `fly launch --local-only` ، ستحتاج إلى تشغيل `fly
deploy --local-only`. لا يسمح Fly.io بسحب صور Docker الخاصة، ولهذا السبب نحتاج
إلى استخدام علامة `--local-only`.


## مقاييس بروميثيوس {#prometheus-metrics}

يعرض Tuist مقاييس Prometheus على `/metrics` لمساعدتك في مراقبة مثيل الاستضافة
الذاتية. تتضمن هذه المقاييس ما يلي:

### مقاييس عميل HTTP Finch {#finch-metrics}

يستخدم Tuist [Finch](https://github.com/sneako/finch) كعميل HTTP ويكشف عن مقاييس
تفصيلية حول طلبات HTTP:

#### طلب المقاييس
- `tuist_prom_ex_finch_request_count_total` - إجمالي عدد طلبات Finch (عداد)
  - التسميات: `finch_name` ، `method` ، `scheme` ، `host` ، `port` ، `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - مدة طلبات HTTP (الرسم
  البياني)
  - التسميات: `finch_name` ، `method` ، `scheme` ، `host` ، `port` ، `status`
  - المجموعات: 10 مللي ثانية، 50 مللي ثانية، 100 مللي ثانية، 250 مللي ثانية، 500
    مللي ثانية، 1 ثانية، 2.5 ثانية، 5 ثوانٍ، 10 ثوانٍ
- `tuist_prom_ex_finch_request_exception_count_total` - إجمالي عدد استثناءات
  طلبات Finch (عداد)
  - التسميات: `finch_name` ، `method` ، `scheme` ، `host` ، `port` ، `kind` ،
    `reason`

#### مقاييس قائمة انتظار تجمع الاتصالات
- `tuist_prom_ex_finch_queue_duration_milliseconds` - الوقت المستغرق في الانتظار
  في قائمة انتظار تجمع الاتصال (الرسم البياني)
  - التسميات: `finch_name` ، `scheme` ، `host` ، `port` ، `pool`
  - المجموعات: 1 مللي ثانية، 5 مللي ثانية، 10 مللي ثانية، 25 مللي ثانية، 50 مللي
    ثانية، 100 مللي ثانية، 250 مللي ثانية، 500 مللي ثانية، 1 ثانية
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - وقت بقية الاتصال في حالة
  خمول قبل استخدامه (الرسم البياني)
  - التسميات: `finch_name` ، `scheme` ، `host` ، `port` ، `pool`
  - المجموعات: 10 مللي ثانية، 50 مللي ثانية، 100 مللي ثانية، 250 مللي ثانية، 500
    مللي ثانية، 1 ثانية، 5 ثوانٍ، 10 ثوانٍ
- `tuist_prom_ex_finch_queue_exception_count_total` - إجمالي عدد استثناءات قائمة
  انتظار Finch (عداد)
  - التسميات: `finch_name` ، `scheme` ، `host` ، `port` ، `kind` ، `reason`

#### مقاييس الاتصال
- `tuist_prom_ex_finch_connect_duration_milliseconds` - الوقت المستغرق في إنشاء
  اتصال (الرسم البياني)
  - التسميات: `finch_name` ، `scheme` ، `host` ، `port` ، `error`
  - المجموعات: 10 مللي ثانية، 50 مللي ثانية، 100 مللي ثانية، 250 مللي ثانية، 500
    مللي ثانية، 1 ثانية، 2.5 ثانية، 5 ثوانٍ
- `tuist_prom_ex_finch_connect_count_total` - إجمالي عدد محاولات الاتصال (عداد)
  - التسميات: `finch_name` ، `scheme` ، `host` ، `port`

#### إرسال المقاييس
- `tuist_prom_ex_finch_send_duration_milliseconds` - الوقت المستغرق في إرسال
  الطلب (الرسم البياني)
  - التسميات: `finch_name` ، `method` ، `scheme` ، `host` ، `port` ، `error`
  - المجموعات: 1 مللي ثانية، 5 مللي ثانية، 10 مللي ثانية، 25 مللي ثانية، 50 مللي
    ثانية، 100 مللي ثانية، 250 مللي ثانية، 500 مللي ثانية، 1 ثانية
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - وقت بقية الاتصال في حالة
  خمول قبل الإرسال (الرسم البياني)
  - التسميات: `finch_name` ، `method` ، `scheme` ، `host` ، `port` ، `error`
  - المجموعات: 1 مللي ثانية، 5 مللي ثانية، 10 مللي ثانية، 25 مللي ثانية، 50 مللي
    ثانية، 100 مللي ثانية، 250 مللي ثانية، 500 مللي ثانية

توفر جميع مقاييس الرسم البياني المتغيرات `_bucket` ، `_sum` ، و `_count` لتحليل
تفصيلي.

### مقاييس أخرى

بالإضافة إلى مقاييس Finch، يعرض Tuist مقاييس لـ:
- أداء الآلة الافتراضية BEAM
- مقاييس منطق الأعمال المخصصة (التخزين، الحسابات، المشاريع، إلخ)
- أداء قاعدة البيانات (عند استخدام البنية التحتية المستضافة من Tuist)

## العمليات {#operations}

يوفر Tuist مجموعة من الأدوات المساعدة على `/ops/` التي يمكنك استخدامها لإدارة
مثيلاتك.

::: warning Authorization
<!-- -->
لا يمكن الوصول إلى نقاط النهاية `/ops/` إلا للأشخاص الذين ترد أسماؤهم في متغير
البيئة `TUIST_OPS_USER_HANDLES`.
<!-- -->
:::

- **الأخطاء (`/ops/errors`):** يمكنك عرض الأخطاء غير المتوقعة التي حدثت في
  التطبيق. هذا مفيد لتصحيح الأخطاء وفهم ما حدث من مشاكل، وقد نطلب منك مشاركة هذه
  المعلومات معنا إذا كنت تواجه مشاكل.
- **لوحة التحكم (`/ops/dashboard`):** يمكنك عرض لوحة تحكم توفر معلومات حول أداء
  التطبيق وحالته (مثل استهلاك الذاكرة والعمليات قيد التشغيل وعدد الطلبات). يمكن
  أن تكون لوحة التحكم هذه مفيدة جدًا لفهم ما إذا كان الجهاز الذي تستخدمه كافيًا
  للتعامل مع الحمل.
