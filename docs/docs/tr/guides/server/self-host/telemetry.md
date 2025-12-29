---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetri {#telemetry}

Tuist sunucusu tarafından toplanan metrikleri
[Prometheus](https://prometheus.io/) ve [Grafana](https://grafana.com/) gibi bir
görselleştirme aracı kullanarak ihtiyaçlarınıza göre uyarlanmış özel bir
gösterge tablosu oluşturabilirsiniz. Prometheus ölçümleri, 9091 numaralı
bağlantı noktasındaki `/metrics` uç noktası aracılığıyla sunulur. Prometheus'un
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
değeri 10_000 saniyeden daha az olarak ayarlanmalıdır (varsayılan değer olan 15
saniyeyi korumanızı öneririz).

## PostHog analitiği {#posthog-analytics}

Tuist, kullanıcı davranışı analizi ve olay takibi için
[PostHog](https://posthog.com/) ile entegre olur. Bu, kullanıcıların Tuist
sunucunuzla nasıl etkileşime girdiğini anlamanıza, özellik kullanımını
izlemenize ve pazarlama sitesi, gösterge tablosu ve API belgeleri genelinde
kullanıcı davranışı hakkında bilgi edinmenize olanak tanır.

### Konfigürasyon {#posthog-configuration}

PostHog entegrasyonu isteğe bağlıdır ve uygun ortam değişkenleri ayarlanarak
etkinleştirilebilir. Yapılandırıldığında Tuist, kullanıcı etkinliklerini, sayfa
görüntülemelerini ve kullanıcı yolculuklarını otomatik olarak izleyecektir.

| Ortam değişkeni         | Açıklama                        | Gerekli | Varsayılan | Örnekler                                          |
| ----------------------- | ------------------------------- | ------- | ---------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | PostHog projesi API anahtarınız | Hayır   |            | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API uç noktası URL'si   | Hayır   |            | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analitik yalnızca `TUIST_POSTHOG_API_KEY` ve `TUIST_POSTHOG_URL` değişkenlerinin
her ikisi de yapılandırıldığında etkinleştirilir. Değişkenlerden biri eksikse,
hiçbir analiz olayı gönderilmeyecektir.
<!-- -->
:::

### Özellikler {#posthog-features}

PostHog etkinleştirildiğinde, Tuist otomatik olarak izler:

- **Kullanıcı kimliği**: Kullanıcılar benzersiz kimlikleri ve e-posta adresleri
  ile tanımlanır
- **Kullanıcı takma adı**: Kullanıcılar, daha kolay tanımlanabilmeleri için
  hesap adlarıyla takma ad alırlar
- **Grup analizi**: Kullanıcılar, segmentlere ayrılmış analizler için seçtikleri
  proje ve organizasyona göre gruplandırılır
- **Sayfa bölümleri**: Olaylar, uygulamanın hangi bölümünün onları oluşturduğunu
  gösteren süper özellikler içerir:
  - `marketing` - Pazarlama sayfalarından ve genel içerikten etkinlikler
  - `gösterge tablosu` - Ana uygulama gösterge tablosundan ve kimliği
    doğrulanmış alanlardan gelen olaylar
  - `api-docs` - API dokümantasyon sayfalarından gelen olaylar
- **Sayfa görüntülemeleri**: Phoenix LiveView kullanarak sayfa gezintisinin
  otomatik takibi
- **Özel olaylar**: Özellik kullanımı ve kullanıcı etkileşimleri için uygulamaya
  özgü olaylar

### Gizlilikle ilgili hususlar {#posthog-privacy}

- Kimliği doğrulanmış kullanıcılar için PostHog, kullanıcının benzersiz
  kimliğini farklı tanımlayıcı olarak kullanır ve e-posta adresini içerir
- Anonim kullanıcılar için PostHog, verileri yerel olarak depolamaktan kaçınmak
  için yalnızca bellekte kalıcılık kullanır
- Tüm analizler kullanıcı gizliliğine saygı gösterir ve en iyi veri koruma
  uygulamalarını takip eder
- PostHog verileri PostHog'un gizlilik politikasına ve yapılandırmanıza göre
  işlenir

## Elixir ölçümleri {#elixir-metrics}

Varsayılan olarak Elixir çalışma zamanı, BEAM, Elixir ve kullandığımız bazı
kütüphanelerin metriklerini dahil ediyoruz. Aşağıda görmeyi bekleyebileceğiniz
metriklerden bazıları verilmiştir:

- [Uygulama](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Hangi metriklerin mevcut olduğunu ve bunların nasıl kullanılacağını öğrenmek
için bu sayfaları kontrol etmenizi öneririz.

## Metrikleri çalıştırır {#runs-metrics}

Tuist Runs ile ilgili bir dizi metrik.

### `tuist_runs_total` (sayaç) {#tuist_runs_total-counter}

Tuist Koşularının toplam sayısı.

#### Etiketler {#tuist-runs-total-tags}

| Etiket  | Açıklama                                                                               |
| ------- | -------------------------------------------------------------------------------------- |
| `isim`  | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test`, vb.                       |
| `is_ci` | Yürütücünün bir CI mı yoksa bir geliştirici makinesi mi olduğunu gösteren bir boolean. |
| `durum` | `0` ` başarılı olması durumunda`, `1` ` başarısız olması durumunda`.                   |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Her tuist çalışmasının milisaniye cinsinden toplam süresi.

#### Etiketler {#tuist-runs-duration-miliseconds-tags}

| Etiket  | Açıklama                                                                               |
| ------- | -------------------------------------------------------------------------------------- |
| `isim`  | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test`, vb.                       |
| `is_ci` | Yürütücünün bir CI mı yoksa bir geliştirici makinesi mi olduğunu gösteren bir boolean. |
| `durum` | `0` ` başarılı olması durumunda`, `1` ` başarısız olması durumunda`.                   |

## Önbellek ölçümleri {#cache-metrics}

Tuist Önbelleği ile ilgili bir dizi metrik.

### `tuist_cache_events_total` (sayaç) {#tuist_cache_events_total-counter}

İkili önbellek olaylarının toplam sayısı.

#### Etiketler {#tuist-cache-events-total-tags}

| Etiket       | Açıklama                                                           |
| ------------ | ------------------------------------------------------------------ |
| `event_type` | `local_hit`, `remote_hit` veya `miss` adreslerinden biri olabilir. |

### `tuist_cache_uploads_total` (sayaç) {#tuist_cache_uploads_total-counter}

İkili önbelleğe yapılan yükleme sayısı.

### `tuist_cache_uploaded_bytes` (toplam) {#tuist_cache_uploaded_bytes-sum}

İkili önbelleğe yüklenen bayt sayısı.

### `tuist_cache_downloads_total` (sayaç) {#tuist_cache_downloads_total-counter}

İkili önbelleğe yapılan indirme sayısı.

### `tuist_cache_downloaded_bytes` (toplam) {#tuist_cache_downloaded_bytes-sum}

İkili önbellekten indirilen bayt sayısı.

---

## Önizleme ölçümleri {#previews-metrics}

Önizleme özelliği ile ilgili bir dizi metrik.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

Yüklenen toplam önizleme sayısı.

### `tuist_previews_downloads_total` (toplam) {#tuist_previews_downloads_total-counter}

İndirilen toplam önizleme sayısı.

---

## Depolama ölçümleri {#storage-metrics}

Eserlerin uzak bir depolama alanında (örn. s3) depolanmasıyla ilgili bir dizi
metrik.

::: tip
<!-- -->
Bu metrikler, depolama işlemlerinin performansını anlamak ve olası darboğazları
belirlemek için kullanışlıdır.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Uzak depolama alanından alınan bir nesnenin boyutu (bayt cinsinden).

#### Etiketler {#tuist-storage-get-object-size-size-bytes-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Uzak depolama alanından bir nesne boyutunu getirme süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

Bir nesne boyutunun uzak depolama alanından kaç kez getirildiği.

#### Etiketler {#tuist-storage-get-object-size-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Uzak depolama alanından tüm nesneleri silme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiket       | Açıklama                                         |
| ------------ | ------------------------------------------------ |
| `proje_slug` | Nesneleri silinmekte olan projenin proje slug'ı. |


### `tuist_storage_delete_all_objects_count` (sayaç) {#tuist_storage_delete_all_objects_count-counter}

Tüm proje nesnelerinin uzak depolama alanından kaç kez silindiğinin sayısı.

#### Etiketler {#tuist-storage-delete-all-objects-count-tags}

| Etiket       | Açıklama                                         |
| ------------ | ------------------------------------------------ |
| `proje_slug` | Nesneleri silinmekte olan projenin proje slug'ı. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Uzak depolama alanına bir yükleme başlatma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_multipart_start_upload_duration_count` (sayaç) {#tuist_storage_multipart_start_upload_duration_count-counter}

Uzak depolama alanına yükleme işleminin başlatılma sayısı.

#### Etiketler {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Bir nesneyi uzak depolama alanından dize olarak getirme süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Bir nesnenin uzak depolama alanından dize olarak getirilme sayısı.

#### Etiketler {#tuist-storage-get-object-as-string-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Uzak depolama alanındaki bir nesnenin varlığını kontrol etme süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Uzak depolama alanında bir nesnenin varlığının kaç kez kontrol edildiği.

#### Etiketler {#tuist-storage-check-object-existence-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Uzak depolama alanındaki bir nesne için önceden atanmış bir indirme URL'si
oluşturma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Uzak depolama alanındaki bir nesne için önceden imzalanmış bir indirme URL'sinin
kaç kez oluşturulduğu.

#### Etiketler {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Uzak depolama alanındaki bir nesne için parça yükleme hazır URL'sinin
oluşturulma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiket           | Açıklama                                          |
| ---------------- | ------------------------------------------------- |
| `object_key`     | Uzak depolama alanındaki nesnenin arama anahtarı. |
| `parça_numarası` | Yüklenmekte olan nesnenin parça numarası.         |
| `upload_id`      | Çok parçalı yüklemenin yükleme kimliği.           |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Uzak depolamadaki bir nesne için parça yükleme önceden atanmış URL'sinin kaç kez
oluşturulduğu.

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiket           | Açıklama                                          |
| ---------------- | ------------------------------------------------- |
| `object_key`     | Uzak depolama alanındaki nesnenin arama anahtarı. |
| `parça_numarası` | Yüklenmekte olan nesnenin parça numarası.         |
| `upload_id`      | Çok parçalı yüklemenin yükleme kimliği.           |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Uzak depolama alanına bir yüklemenin tamamlanma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |
| `upload_id`  | Çok parçalı yüklemenin yükleme kimliği.           |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Uzak depolama alanına bir yüklemenin tamamlandığı toplam sayı.

#### Etiketler {#tuist-storage-multipart-complete-upload-count-tags}

| Etiket       | Açıklama                                          |
| ------------ | ------------------------------------------------- |
| `object_key` | Uzak depolama alanındaki nesnenin arama anahtarı. |
| `upload_id`  | Çok parçalı yüklemenin yükleme kimliği.           |

---

## Kimlik doğrulama ölçümleri {#authentication-metrics}

Kimlik doğrulama ile ilgili bir dizi metrik.

### `tuist_authentication_token_refresh_error_total` (sayaç) {#tuist_authentication_token_refresh_error_total-counter}

Belirteç yenileme hatalarının toplam sayısı.

#### Etiketler {#tuist-authentication-token-refresh-error-total-tags}

| Etiket        | Açıklama                                                                               |
| ------------- | -------------------------------------------------------------------------------------- |
| `cli_version` | Hatayla karşılaşılan Tuist CLI sürümü.                                                 |
| `Sebep`       | Belirteç yenileme hatasının nedeni, örneğin `invalid_token_type` veya `invalid_token`. |

---

## Proje ölçümleri {#projects-metrics}

Projelerle ilgili bir dizi metrik.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

Toplam proje sayısı.

---

## Hesap metrikleri {#accounts-metrics}

Hesaplarla (kullanıcılar ve kuruluşlar) ilgili bir dizi metrik.

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

Toplam kuruluş sayısı.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

Toplam kullanıcı sayısı.


## Veritabanı ölçümleri {#database-metrics}

Veritabanı bağlantısıyla ilgili bir dizi metrik.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Bir kuyrukta bekleyen ve bir veritabanı bağlantısına atanmayı bekleyen
veritabanı sorgularının sayısı.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Bir veritabanı sorgusuna atanmaya hazır olan veritabanı bağlantılarının sayısı.


### `tuist_repo_pool_db_connection_connected` (sayaç) {#tuist_repo_pool_db_connection_connected-counter}

Veritabanına kurulan bağlantıların sayısı.

### `tuist_repo_pool_db_connection_disconnected` (sayaç) {#tuist_repo_pool_db_connection_disconnected-counter}

Veritabanıyla bağlantısı kesilen bağlantı sayısı.

## HTTP ölçümleri {#http-metrics}

Tuist'in HTTP aracılığıyla diğer hizmetlerle etkileşimleriyle ilgili bir dizi
metrik.

### `tuist_http_request_count` (sayaç) {#tuist_http_request_count-last_value}

Giden HTTP isteklerinin sayısı.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

Giden isteklerin sürelerinin toplamı (bir bağlantıya atanmak için bekledikleri
süre dahil).

### `tuist_http_request_duration_nanosecond_bucket` (dağıtım) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Giden taleplerin süresinin dağılımı (bir bağlantıya atanmak için bekledikleri
süre dahil).

### `tuist_http_queue_count` (sayaç) {#tuist_http_queue_count-counter}

Havuzdan alınan isteklerin sayısı.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantı almak için geçen süre.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_queue_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantı almak için geçen süre.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dağıtım) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_connection_count` (sayaç) {#tuist_http_connection_count-counter}

Kurulan bağlantıların sayısı.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Bir ana bilgisayara karşı bağlantı kurmak için geçen süre.

### `tuist_http_connection_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Bir ana bilgisayara karşı bağlantı kurmak için gereken sürenin dağılımı.

### `tuist_http_send_count` (sayaç) {#tuist_http_send_count-counter}

Havuzdan bir bağlantıya atandıktan sonra gönderilen istek sayısı.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen
süre.

### `tuist_http_send_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen
sürenin dağılımı.

### `tuist_http_receive_count` (sayaç) {#tuist_http_receive_count-counter}

Gönderilen isteklerden alınan yanıtların sayısı.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Yanıt almak için harcanan süre.

### `tuist_http_receive_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Yanıt almak için harcanan zamanın dağılımı.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Kuyrukta mevcut olan bağlantı sayısı.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Kullanımda olan kuyruk bağlantılarının sayısı.
