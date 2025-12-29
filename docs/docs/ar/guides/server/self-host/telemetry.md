---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# القياس عن بُعد {#telemetry}

يمكنك استيعاب المقاييس التي يجمعها خادم تويست باستخدام [Prometheus]
(https://prometheus.io/) وأداة تصور مثل [Grafana] (https://grafana.com/) لإنشاء
لوحة معلومات مخصصة مصممة خصيصًا لتلبية احتياجاتك. يتم تقديم مقاييس بروميثيوس عبر
نقطة النهاية `/metrics` على المنفذ 9091. يجب تعيين [scrape_interval]
(https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) في
بروميثيوس على أقل من 10_000 ثانية (نوصي بالحفاظ على الإعداد الافتراضي 15 ثانية).

## تحليلات بوست هوغ {#posthog-analytics}

يتكامل تويست مع [PostHog] (https://posthog.com/) لتحليل سلوك المستخدم وتتبع
الأحداث. يتيح لك ذلك فهم كيفية تفاعل المستخدمين مع خادم تويست الخاص بك، وتتبع
استخدام الميزات، واكتساب رؤى حول سلوك المستخدم عبر موقع التسويق ولوحة المعلومات
ووثائق واجهة برمجة التطبيقات.

### تهيئة {#posthog-configuration}

يعد تكامل PostHog اختياريًا ويمكن تمكينه عن طريق تعيين متغيرات البيئة المناسبة.
عند تهيئته، سيقوم تويست تلقائيًا بتتبع أحداث المستخدم، ومشاهدات الصفحة، ورحلات
المستخدم.

| متغير البيئة                    | الوصف                                               | مطلوب   | افتراضي | مثال على ذلك                                                    |
| ------------------------------- | --------------------------------------------------- | ------- | ------- | --------------------------------------------------------------- |
| `tuist_posthog_api_key_API_key` | مفتاح واجهة برمجة التطبيقات لمشروع PostHog الخاص بك | لا يوجد |         | `phc_fpR9c0Hs5Hs5H5H5VXXUsupUsupU1I0WLWLEq366FaZH6H6HJR3lRIWVR` |
| `tuist_posthog_url`             | عنوان URL نقطة نهاية واجهة برمجة تطبيقات PostHog    | لا يوجد |         | `https://eu.i.posthog.com`                                      |

::: info عن تمكين التحليلات
يتم تمكين التحليلات فقط عندما يتم تكوين كل من `TUIST_POSTHOG_API_KEY` و
`TUIST_POSTHOG_URL`. إذا كان أي من المتغيرين مفقودًا، فلن يتم إرسال أي أحداث
تحليلية.
:::

### الميزات {#posthog-features}

عند تمكين PostHog، يتتبع تويست تلقائيًا:

- **تعريف المستخدم**: يتم التعرف على المستخدمين من خلال معرفهم الفريد وعنوان
  بريدهم الإلكتروني
- **تسمية المستخدم المستعار**: يتم تسمية المستخدمين بأسماء مستعارة بأسماء
  حساباتهم لتسهيل التعرف عليهم
- **تحليلات المجموعة**: يتم تجميع المستخدمين حسب المشروع والمؤسسة التي اختاروها
  لإجراء تحليلات مجزأة
- **أقسام الصفحة**: تتضمن الأحداث خصائص فائقة تشير إلى قسم التطبيق الذي أنشأها:
  - `تسويق` - أحداث من صفحات التسويق والمحتوى العام
  - `لوحة التحكم` - الأحداث من لوحة تحكم التطبيق الرئيسية والمناطق المصادق عليها
  - `api-docs` - أحداث من صفحات وثائق API
- **مشاهدات الصفحة**: التتبع التلقائي لتصفح الصفحات باستخدام فينيكس لايف فيو
- **أحداث مخصصة**: أحداث خاصة بالتطبيق لاستخدام الميزة وتفاعلات المستخدم

### اعتبارات الخصوصية {#posthog-privacy}

- بالنسبة للمستخدمين الذين تمت مصادقتهم، يستخدم PostHog المعرف الفريد للمستخدم
  كمعرف مميز ويتضمن عنوان بريده الإلكتروني
- بالنسبة للمستخدمين مجهولي الهوية، يستخدم PostHog الثبات في الذاكرة فقط لتجنب
  تخزين البيانات محليًا
- تحترم جميع التحليلات خصوصية المستخدم وتتبع أفضل ممارسات حماية البيانات
- تتم معالجة بيانات PostHog وفقًا لسياسة خصوصية PostHog وتكوينك

## مقاييس إليكسير {#elixir-metrics}

بشكل افتراضي، نقوم بتضمين مقاييس وقت تشغيل إليكسير و BEAM وإليكسير وبعض المكتبات
التي نستخدمها. فيما يلي بعض المقاييس التي يمكنك توقع رؤيتها:

- [التطبيق] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [بيم] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [فينيكس] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [فينيكس لايف فيو]
  (https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [إكتو] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [أوبان] (https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

نوصي بمراجعة تلك الصفحات لمعرفة المقاييس المتاحة وكيفية استخدامها.

## تشغيل المقاييس {#runs-metrics}

مجموعة من المقاييس المتعلقة بتشغيلات تويست.

### `tuist_runs_total` (عداد) {#tuist_runs_total_total-counter}

إجمالي عدد مرات تشغيل تويست.

#### الوسوم {#tuist-runist-runs-total-tags}

| الوسم    | الوصف                                                           |
| -------- | --------------------------------------------------------------- |
| `الاسم`  | اسم الأمر `tuist` الذي تم تشغيله، مثل `بناء` ، `اختبار` ، إلخ.  |
| `is_ci`  | قيمة منطقية تشير إلى ما إذا كان المنفِّذ مخبر سري أو جهاز مطور. |
| `الحالة` | `0` في حالة `النجاح ،` ، `1` في حالة `الفشل`.                   |

### `tuist_runs_duration_duration_milliseconds` (رسم بياني) {#tuist_runs_duration_duration_milliseconds_milliseconds-histogram}

المدة الإجمالية لكل تشغيل تويست بالمللي ثانية.

#### العلامات {#tuist-runs-duration-duration-miliseconds-tags}

| الوسم    | الوصف                                                           |
| -------- | --------------------------------------------------------------- |
| `الاسم`  | اسم الأمر `tuist` الذي تم تشغيله، مثل `بناء` ، `اختبار` ، إلخ.  |
| `is_ci`  | قيمة منطقية تشير إلى ما إذا كان المنفِّذ مخبر سري أو جهاز مطور. |
| `الحالة` | `0` في حالة `النجاح ،` ، `1` في حالة `الفشل`.                   |

## مقاييس ذاكرة التخزين المؤقت {#cache-metrics}

مجموعة من المقاييس المتعلقة بذاكرة التخزين المؤقت لتويست.

### `tuist_cache_cache_events_total` (عداد) {#tuist_cache_cache_events_total-counter}

إجمالي عدد أحداث ذاكرة التخزين المؤقت الثنائية.

#### الوسوم {#tuist-cuist-cache-events-total-tags}

| الوسم       | الوصف                                                            |
| ----------- | ---------------------------------------------------------------- |
| `نوع_الحدث` | يمكن أن يكون إما من `إصابة محلية` أو `إصابة عن بُعد` أو `تفويت`. |

### `tuist_cache_cuploads_uploads_total` (عداد) {#tuist_cache_uploads_uploads_total-counter}

عدد عمليات التحميل إلى ذاكرة التخزين المؤقت الثنائية.

### `tuist_cache_cache_uploaded_bytes` (المجموع) {#tuist_cache_cache_uploaded_bytes-sum}

عدد وحدات البايت التي تم تحميلها إلى ذاكرة التخزين المؤقت الثنائية.

### `tuist_cache_cdownloads_downloads_total` (عداد) {#tuist_cache_downloads_downloads_total-counter}

عدد التنزيلات إلى ذاكرة التخزين المؤقت الثنائية.

### `tuist_cache_cache_downloaded_bytes` (المجموع) {#tuist_cache_cache_downloaded_bytes-sum}

عدد وحدات البايت التي تم تنزيلها من ذاكرة التخزين المؤقت الثنائية.

---

## مقاييس المعاينة {#previews-metrics}

مجموعة من المقاييس المتعلقة بميزة المعاينات.

### `tuist_previews_previews_uploads_total` (المجموع) {#tuist_previews_uploads_uploads_total-counter}

إجمالي عدد المعاينات التي تم تحميلها.

### `tuist_previews_previews_downloads_total` (المجموع) {#tuist_previews_downloads_total-counter}

إجمالي عدد المعاينات التي تم تنزيلها.

---

## مقاييس التخزين {#storage-metrics}

مجموعة من المقاييس المتعلقة بتخزين القطع الأثرية في مخزن بعيد (مثل s3).

::: tip
هذه المقاييس مفيدة لفهم أداء عمليات التخزين وتحديد الاختناقات المحتملة.
:::

### `tuist_storage_get_get_object_size_size_size_size_bytes` (رسم بياني) {#tuist_storage_get_get_object_size_size_size_size_bytes-histogram}

حجم (بالبايت) الكائن الذي تم جلبه من وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-get-get-object-size-size-size-bytes-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |


### `tuist_storage_get_get_object_size_size_duration_miliseconds` (رسم بياني) {#tuist_storage_get_get_object_size_duration_miliseconds_miliseconds-histogram}

المدة (بالمللي ثانية) لجلب حجم كائن من وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-get-get-object-size-size-duration-miliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |


### `tuist_storage_get_get_obget_size_size_count` (عداد) {#tuist_storage_get_get_size_size_count_count}

عدد المرات التي تم فيها جلب حجم الكائن من وحدة التخزين عن بُعد.

#### العلامات {#tuist-storage-get-get-object-size-size-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_delete_all_dall_objects_duration_milliseconds_milliseconds` (رسم بياني) {#tuist_storage_delete_all_dall_objects_duration_duration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) لحذف جميع الكائنات من وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-delete-all-objects-duration-dilliseconds-milliseconds-tags}

| الوسم           | الوصف                                       |
| --------------- | ------------------------------------------- |
| `سبيكة_المشروع` | سبيكة المشروع للمشروع الذي يتم حذف كائناته. |


### `tuist_storage_delete_all_storage_delete_all_objects_counts_count` (عداد) {#tuist_storage_delete_all_objects_counts_count}

عدد المرات التي تم فيها حذف جميع كائنات المشروع من وحدة التخزين عن بُعد.

#### العلامات {#tuist-storage-delete-all-objects-counts-count-tags}

| الوسم           | الوصف                                       |
| --------------- | ------------------------------------------- |
| `سبيكة_المشروع` | سبيكة المشروع للمشروع الذي يتم حذف كائناته. |


### `tuist_storage_multipart_start_start_upart_upart_upart_upload_duration_milliseconds` (رسم بياني) {#tuist_storage_multipart_start_upload_duration_duration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) لبدء التحميل إلى وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-multipart-start-start-up-up-upload-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_multipart_start_start_upart_upload_dupuration_duration_count` (عداد) {#tuist_storage_multipart_start_stupload_dupload_duration_duration_count}

عدد مرات بدء التحميل إلى وحدة التخزين عن بُعد.

#### العلامات {#tuist-storage-multipart-start-start-up-up-upload-duration-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |


### `tuist_storage_get_get_object_as_string_duration_milliseconds` (رسم بياني) {#tuist_storage_get_object_as_string_duration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) لجلب كائن كسلسلة من وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-get-get-object-as-string-duration-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_get_get_object_as_string_count` (العد) {#tuist_storage_get_get_object_as_string_as_string_count}

عدد المرات التي تم فيها جلب كائن كسلسلة من وحدة التخزين البعيدة.

#### الوسوم {#tuist-storage-get-get-object-as-string-count-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |


### `tuist_storage_stcheck_object_existence_dexence_duration_milliseconds` (رسم بياني) {#tuist_storage_stcheck_object_existence_dexuration_dexuration_dexuration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) للتحقق من وجود كائن في وحدة التخزين البعيدة.

#### العلامات {#tuist-stuist-st storage-check-object-exist-exist-exence-dexuration-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_stecheck_object_exist_existence_count` (العد) {#tuist_storage_steccheck_object_existence_count_count}

عدد المرات التي تم فيها التحقق من وجود كائن في المخزن البعيد.

#### العلامات {#tuist-stouist-st storage-sthck-oist-ject-exist-exist-exist-exist-exist-ount-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_generate_download_download_presigned_url_url_durl_duration_milliseconds` (رسم بياني) {#tuist_storage_generate_download_durl_durl_durl_durl_durl_durl_duration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) لإنشاء عنوان URL محدد مسبقاً للتنزيل لكائن في وحدة التخزين
البعيدة.

#### العلامات {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |


### `tuist_storage_generate_downloadate_download_presigned_url_url_count` (العد) {#tuist_storage_generate_download_presigned-url-count-count}

عدد المرات التي تم فيها إنشاء عنوان URL محدد مسبقاً للتنزيل لكائن في وحدة
التخزين البعيدة.

#### العلامات {#tuist-storage-generate-download-presigned-url-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |

### `tuist_storage_multipart_generate_upload_upload_part_presigned_purl_purl_purl_milliseconds_milliseconds` (رسم بياني) {#tuist_storage_multipart_generate_upload_upload_part_presigned_url_murl_duration_milliseconds_millisecram}

المدة (بالمللي ثانية) لإنشاء عنوان URL محدد مسبقاً لتحميل جزء من التحميل لكائن
في وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-multipart-multipart-generate-upload-part-presigned-url-durl-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |
| `رقم_الجزء`    | رقم الجزء الخاص بالكائن الذي يتم تحميله.       |
| `تحميل_معرف`   | معرف التحميل الخاص بالتحميل متعدد الأجزاء.     |

### `tuist_storage_multipart_generate_upload_upload_part_presigned_purl_count` (العد) {#tuist_storage_multipart_generate_upload_upload_part_presigned_url_count_count}

عدد المرات التي تم فيها إنشاء عنوان URL محدد مسبقاً لتحميل جزء لكائن في وحدة
التخزين البعيدة.

#### العلامات {#tuist-storage-multipart-multipart-generate-upload-part-presigned-part-url-count-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |
| `رقم_الجزء`    | رقم الجزء الخاص بالكائن الذي يتم تحميله.       |
| `تحميل_معرف`   | معرف التحميل الخاص بالتحميل متعدد الأجزاء.     |

### `tuist_storage_multipart_complete_compload_uplete_upload_duration_milliseconds` (رسم بياني) {#tuist_storage_multipart_complete_upload_duration_milliseconds_milliseconds-histogram}

المدة (بالمللي ثانية) لإكمال التحميل إلى وحدة التخزين البعيدة.

#### العلامات {#tuist-storage-multipart-complete-upload-up-up-upload-duration-milliseconds-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |
| `تحميل_معرف`   | معرف التحميل الخاص بالتحميل متعدد الأجزاء.     |


### `tuist_storage_storage_multipart_complete_complete_upload_count` (العد) {#tuist_storage_multipart_complete_complete_upload_count_count}

العدد الإجمالي لمرات اكتمال التحميل إلى وحدة التخزين عن بُعد.

#### العلامات {#tuist-storage-multipart-multipart-complete-upload-up-upount-count-tags}

| الوسم          | الوصف                                          |
| -------------- | ---------------------------------------------- |
| `مفتاح_الكائن` | مفتاح البحث عن الكائن في وحدة التخزين البعيدة. |
| `تحميل_معرف`   | معرف التحميل الخاص بالتحميل متعدد الأجزاء.     |

---

## مقاييس المصادقة {#authentication-metrics}

مجموعة من المقاييس المتعلقة بالمصادقة.

### `tuist_authentication_authentication_token_refresh_refresh_error_total` (عداد) {#tuist_authentication_autoken_token_refresh_refresh_error_terror_total-counter}

العدد الإجمالي لأخطاء تحديث الرمز المميز.

#### العلامات {#tuist-autuist-authentication-token-refresh-ror-total-tags}

| الوسم       | الوصف                                                                            |
| ----------- | -------------------------------------------------------------------------------- |
| `cli_إصدار` | إصدار Twist CLI الذي واجه الخطأ.                                                 |
| `السبب`     | سبب خطأ تحديث الرمز المميز، مثل `غير صالح_رمز_مُرمز_نوع` أو `غير صالح_رمز مميز`. |

---

## مقاييس المشاريع {#projects-metrics}

مجموعة من المقاييس المتعلقة بالمشاريع.

### `tuist_projects_projects_total` (آخر_قيمة) {#tuist_projects_total-last_value}

العدد الإجمالي للمشاريع.

---

## مقاييس الحسابات {#accounts-metrics}

مجموعة من المقاييس المتعلقة بالحسابات (المستخدمين ومنتديات المجموعة).

### `tuist_accounts_accounts_organizations_total` (آخر_قيمة) {#tuist_accounts_accounts_organizations_total-last_value}

إجمالي عدد المنظمات.

### `tuist_accounts_accounts_accounts_users_total` (آخر_قيمة) {#tuist_accounts_accounts_accusers_total-last_value}

إجمالي عدد المستخدمين.


## مقاييس قاعدة البيانات {#database-metrics}

مجموعة من المقاييس المتعلقة باتصال قاعدة البيانات.

### `tuist_repo_repo_pool_checkout_queout_queue_length` (آخر_قيمة) {#tuist_repo_repo_pool_checkout_queout_queue_length_length_last_value}

عدد استعلامات قاعدة البيانات الموجودة في قائمة الانتظار في انتظار تعيينها لاتصال
قاعدة البيانات.

### `tuist_repo_repo_repo_pool_ready_conn_count` (آخر_قيمة) {#tuist_repo_repo_repo_pool_ready_conn_conn_count_last_value}

عدد اتصالات قاعدة البيانات الجاهزة للتعيين لاستعلام قاعدة البيانات.


### `tuist_repo_repo_dpool_dpool_db_db_connection_connconnected` (عداد) {#tuist_repo_repo_dpool_db_db_connection_connconnected-counter}

عدد الاتصالات التي تم إنشاؤها بقاعدة البيانات.

### `tuist_repo_repo_pool_db_db_db_dconnection_disconnected` (عداد) {#tuist_repo_repo_pool_db_db_dconnection_disconnected_disconnected-counter}

عدد الاتصالات التي تم قطع اتصالها بقاعدة البيانات.

## مقاييس HTTP {#http-metrics}

مجموعة من المقاييس المتعلقة بتفاعلات تويست مع الخدمات الأخرى عبر HTTP.

### `tuist_http_http_request_count` (عداد) {#tuist_http_http_request_count_count-last_value}

عدد طلبات HTTP الصادرة.

### `tuist_http_http_request_request_duration_nanosecond_nanosecond_sum` (المجموع) {#tuist_http_http_request_dquest_duration_nanosecond_sum-lanosecond_sum-last_value}

مجموع مدة الطلبات الصادرة (بما في ذلك الوقت الذي استغرقته في انتظار تعيين
اتصال).

### `tuist_http_http_request_request_duration_nanosecond_nanosecond_bucket` (التوزيع) {#tuist_http_http_request_duration_nanosecond_nanosecond_bucket-distribute}
توزيع مدة الطلبات الصادرة (بما في ذلك الوقت الذي استغرقته في انتظار تعيين
اتصال).

### `tuist_http_http_queue_count` (عداد) {#tuist_http_http_queue_queue_count-counter}

عدد الطلبات التي تم استردادها من المجمع.

### `tuist_http_http_queue_due_due_duration_nanoseconds_nanoseconds_sum` (المجموع) {#tuist_http_queue_due_due_duration_nanoseconds_nanoseconds_sum-sum}

الوقت الذي يستغرقه استرداد اتصال من المجمع.

### `tuist_http_http_quettp_queue_queue_idue_time_nanoseconds_nanoseconds_nanoseconds_sum` (المجموع) {#tuist_http_quettp_queue_idue_time_nanoseconds_nanoseconds_sum-sum}

الوقت الذي ظل فيه الاتصال خاملاً في انتظار الاسترداد.

### `tuist_http_http_queue_due_due_duration_nanoseconds_nanoseconds_bucket` (التوزيع) {#tuist_http_queue_due_due_duration_nanoseconds_nanoseconds_bucket-distribute}

الوقت الذي يستغرقه استرداد اتصال من المجمع.

### `tuist_http_http_quettp_queue_queue_idue_idue_time_nanoseconds_nanoseconds_nanoseconds_bucket` (التوزيع) {#tuist_http_quettp_queue_idue_idue_time_nanoseconds_nanoseconds_bucket_bucket-distribute}

الوقت الذي ظل فيه الاتصال خاملاً في انتظار الاسترداد.

### `tuist_http_http_connection_count` (عداد) {#tuist_http_http_hconnection_count_count}

عدد الاتصالات التي تم إنشاؤها.

### `tuist_http_http_donnection_donnection_duration_nanoseconds_nanoseconds_sum` (المجموع) {#tuist_http_http_donnection_donnection_duration_nanoseconds_nanoseconds_sum-sum}

الوقت الذي يستغرقه إنشاء اتصال مقابل مضيف.

### `tuist_http_http_donnection_dconnection_duration_nanoseconds_nanoseconds_nanoseconds_bucket` (التوزيع) {#tuist_http_http_donnection_donnection_duration_nanoseconds_nanoseconds_bucket-distribute}

توزيع الوقت الذي يستغرقه إنشاء اتصال مقابل مضيف.

### `tuist_http_http_send_count` (عداد) {#tuist_http_http_send_count_count-counter}

عدد الطلبات التي تم إرسالها بمجرد تعيينها إلى اتصال من مجموعة الاتصالات.

### `tuist_http_http_send_send_duration_nanoseconds_nanoseconds_nanoseconds_sum` (المجموع) {#tuist_http_http_send_send_duration_nanoseconds_nanoseconds_sum-sum}

الوقت الذي تستغرقه الطلبات لإكمالها بمجرد تعيينها إلى اتصال من مجموعة الاتصالات.

### `tuist_http_http_send_send_duration_nanoseconds_nanoseconds_nanoseconds_bucket` (التوزيع) {#tuist_http_http_send_duration_nanoseconds_nanoseconds_bucket-distribute}

توزيع الوقت الذي تستغرقه الطلبات لإكمالها بمجرد تعيينها إلى اتصال من مجموعة
الاتصالات.

### `tuist_http_http_receive_count` (عداد) {#tuist_http_http_receive_count_count}

عدد الردود التي تم استلامها من الطلبات المرسلة.

### `tuist_http_http_receive_dreceive_duration_nanoseconds_nanoseconds_sum` (المجموع) {#tuist_http_http_receive_duration_nanoseconds_nanoseconds_sum-sum}

الوقت المستغرق في تلقي الردود.

### `tuist_http_http_receive_dreceive_duration_nanoseconds_nanoseconds_nanoseconds_bucket` (التوزيع) {#tuist_http_http_receive_duration_nanoseconds_nanoseconds_nanoseconds_bucket-distribute}

توزيع الوقت المستغرق في تلقي الردود.

### `tuist_http_http_queue_available_avconnections` (آخر_قيمة) {#tuist_http_queue_available_queue_avconnections-last_valconnections-last_value}

عدد الاتصالات المتوفرة في قائمة الانتظار.

### `tuist_http_http_queue_in_in_use_connections` (آخر_قيمة) {#tuist_http_queue_in_use_in_connections-last_value}

عدد اتصالات قائمة الانتظار قيد الاستخدام.
