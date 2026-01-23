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
görselleştirme aracı kullanarak alabilir ve ihtiyaçlarınıza göre özelleştirilmiş
bir gösterge paneli oluşturabilirsiniz. Prometheus metrikleri, 9091 numaralı
bağlantı noktasında `/metrics` uç noktası üzerinden sunulur. Prometheus'un
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
değeri 10_000 saniyeden az olarak ayarlanmalıdır (varsayılan 15 saniye değerini
korumanızı öneririz).

## PostHog analitiği {#posthog-analytics}

Tuist, kullanıcı davranış analizi ve olay izleme için
[PostHog](https://posthog.com/) ile entegre çalışır. Bu sayede, kullanıcıların
Tuist sunucunuzla nasıl etkileşimde bulunduğunu anlayabilir, özellik kullanımını
izleyebilir ve pazarlama sitesi, kontrol paneli ve API belgeleri genelinde
kullanıcı davranışları hakkında bilgi edinebilirsiniz.

### Yapılandırma {#posthog-configuration}

PostHog entegrasyonu isteğe bağlıdır ve uygun ortam değişkenleri ayarlanarak
etkinleştirilebilir. Yapılandırıldığında, Tuist kullanıcı olaylarını, sayfa
görüntülemelerini ve kullanıcı yolculuklarını otomatik olarak izler.

| Ortam değişkeni         | Açıklama                        | Gerekli | Varsayılan | Örnekler                                          |
| ----------------------- | ------------------------------- | ------- | ---------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | PostHog projenizin API anahtarı | Hayır   |            | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | PostHog API uç nokta URL'si     | Hayır   |            | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analitik, yalnızca `TUIST_POSTHOG_API_KEY` ve `TUIST_POSTHOG_URL`
yapılandırıldığında etkinleştirilir. Herhangi bir değişken eksikse, analitik
olayları gönderilmez.
<!-- -->
:::

### Özellikler {#posthog-features}

PostHog etkinleştirildiğinde, Tuist otomatik olarak şunları izler:

- **Kullanıcı kimliği**: Kullanıcılar, benzersiz kimlik numaraları ve e-posta
  adresleri ile tanımlanır.
- **Kullanıcı takma adı**: Kullanıcılar, daha kolay tanımlanabilmeleri için
  hesap adlarıyla takma adlandırılır.
- **Grup analizi**: Kullanıcılar, seçtikleri proje ve organizasyona göre
  gruplandırılır ve segmentlere ayrılmış analizler yapılır.
- **Sayfa bölümleri**: Olaylar, uygulamanın hangi bölümünün bunları
  oluşturduğunu gösteren süper özellikler içerir:
  - `pazarlama` - Pazarlama sayfalarından ve halka açık içeriklerden etkinlikler
  - `dashboard` - Ana uygulama panosundan ve kimliği doğrulanmış alanlardan
    gelen olaylar
  - `api-docs` - API belgeleri sayfalarından olaylar
- **Sayfa görüntülemeleri**: Phoenix LiveView kullanarak sayfa geziniminin
  otomatik olarak izlenmesi
- **Özel olaylar**: Özellik kullanımı ve kullanıcı etkileşimleri için uygulamaya
  özgü olaylar

### Gizlilik hususları {#posthog-privacy}

- Kimliği doğrulanmış kullanıcılar için PostHog, kullanıcının benzersiz
  kimliğini ayırt edici tanımlayıcı olarak kullanır ve e-posta adresini ekler.
- Anonim kullanıcılar için PostHog, verileri yerel olarak depolamaktan kaçınmak
  için yalnızca bellek kalıcılığı kullanır.
- Tüm analizler kullanıcı gizliliğine saygı gösterir ve veri koruma en iyi
  uygulamalarına uyar.
- PostHog verileri, PostHog'un gizlilik politikası ve sizin yapılandırmanıza
  göre işlenir.

## Elixir metrikleri {#elixir-metrics}

Varsayılan olarak Elixir çalışma zamanı, BEAM, Elixir ve kullandığımız bazı
kütüphanelerin metriklerini dahil ediyoruz. Aşağıda görebileceğiniz bazı
metrikler bulunmaktadır:

- [Uygulama](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Hangi metriklerin mevcut olduğunu ve bunların nasıl kullanıldığını öğrenmek için
bu sayfaları kontrol etmenizi öneririz.

## Metrikleri çalıştırır {#runs-metrics}

Tuist Runs ile ilgili bir dizi metrik.

### `tuist_runs_total` (sayaç) {#tuist_runs_total-counter}

Toplam Tuist Koşusu sayısı.

#### Etiketler {#tuist-runs-total-tags}

| Etiket  | Açıklama                                                                                   |
| ------- | ------------------------------------------------------------------------------------------ |
| `name`  | `tuist` komutunun adı, örneğin `build`, `test`, vb.                                        |
| `is_ci` | Yürütücünün bir CI mi yoksa geliştiricinin makinesi mi olduğunu belirten bir boole değeri. |
| `durum` | `0` ` başarı durumunda`, `1` ` başarısızlık durumunda`.                                    |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Her tuist'in toplam süresi milisaniye cinsindendir.

#### Etiketler {#tuist-runs-duration-miliseconds-tags}

| Etiket  | Açıklama                                                                                   |
| ------- | ------------------------------------------------------------------------------------------ |
| `name`  | `tuist` komutunun adı, örneğin `build`, `test`, vb.                                        |
| `is_ci` | Yürütücünün bir CI mi yoksa geliştiricinin makinesi mi olduğunu belirten bir boole değeri. |
| `durum` | `0` ` başarı durumunda`, `1` ` başarısızlık durumunda`.                                    |

## Önbellek ölçümleri {#cache-metrics}

Tuist Önbelleği ile ilgili bir dizi ölçüm.

### `tuist_cache_events_total` (sayaç) {#tuist_cache_events_total-counter}

Toplam ikili önbellek olayı sayısı.

#### Etiketler {#tuist-cache-events-total-tags}

| Etiket       | Açıklama                                        |
| ------------ | ----------------------------------------------- |
| `event_type` | `local_hit`, `remote_hit` veya `miss` olabilir. |

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

### `tuist_previews_uploads_total` (toplam) {#tuist_previews_uploads_total-counter}

Yüklenen önizlemelerin toplam sayısı.

### `tuist_previews_downloads_total` (toplam) {#tuist_previews_downloads_total-counter}

İndirilen önizlemelerin toplam sayısı.

---

## Depolama ölçütleri {#storage-metrics}

Uzak depolama alanında (ör. s3) artefaktların depolanmasıyla ilgili bir dizi
metrik.

::: tip
<!-- -->
Bu ölçütler, depolama işlemlerinin performansını anlamak ve olası darboğazları
belirlemek için yararlıdır.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Uzak depolamadan alınan bir nesnenin boyutu (bayt cinsinden).

#### Etiketler {#tuist-storage-get-object-size-size-bytes-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Uzak depolamadan bir nesne boyutunu alma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_size_count` (sayaç) {#tuist_storage_get_object_size_count-counter}

Uzak depolama alanından nesne boyutunun alınma sayısı.

#### Etiketler {#tuist-storage-get-object-size-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Uzak depolama alanından tüm nesneleri silme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiket         | Açıklama                                 |
| -------------- | ---------------------------------------- |
| `project_slug` | Nesneleri silinen projenin proje slug'ı. |


### `tuist_storage_delete_all_objects_count` (sayaç) {#tuist_storage_delete_all_objects_count-counter}

Tüm proje nesnelerinin uzak depolama alanından silinme sayısı.

#### Etiketler {#tuist-storage-delete-all-objects-count-tags}

| Etiket         | Açıklama                                 |
| -------------- | ---------------------------------------- |
| `project_slug` | Nesneleri silinen projenin proje slug'ı. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Uzak depolama alanına yükleme işleminin başlamasının süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_multipart_start_upload_duration_count` (sayaç) {#tuist_storage_multipart_start_upload_duration_count-counter}

Uzak depolama alanına yükleme işleminin başlatıldığı sayı.

#### Etiketler {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Uzak depolama alanından bir nesneyi dize olarak getirmenin süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Bir nesnenin uzak depolama alanından dize olarak getirilme sayısı.

#### Etiketler {#tuist-storage-get-object-as-string-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Uzak depolamada bir nesnenin varlığını kontrol etmenin süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Uzak depolamada bir nesnenin varlığı kaç kez kontrol edildi.

#### Etiketler {#tuist-storage-check-object-existence-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için önceden imzalanmış indirme URL'si oluşturma
süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Uzak depolamadaki bir nesne için önceden imzalanmış indirme URL'si oluşturulma
sayısı.

#### Etiketler {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için önceden imzalanmış bir parça yükleme URL'si
oluşturmanın süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiket        | Açıklama                                   |
| ------------- | ------------------------------------------ |
| `object_key`  | Uzak depolamadaki nesnenin arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası.          |
| `upload_id`   | Çok parçalı yüklemenin yükleme kimliği.    |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Uzak depolamadaki bir nesne için önceden imzalanmış URL'nin kaç kez
oluşturulduğu.

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiket        | Açıklama                                   |
| ------------- | ------------------------------------------ |
| `object_key`  | Uzak depolamadaki nesnenin arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası.          |
| `upload_id`   | Çok parçalı yüklemenin yükleme kimliği.    |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Uzak depolama alanına yükleme işleminin tamamlanma süresi (milisaniye
cinsinden).

#### Etiketler {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |
| `upload_id`  | Çok parçalı yüklemenin yükleme kimliği.    |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Uzak depolama alanına yükleme işleminin tamamlandığı toplam sayı.

#### Etiketler {#tuist-storage-multipart-complete-upload-count-tags}

| Etiket       | Açıklama                                   |
| ------------ | ------------------------------------------ |
| `object_key` | Uzak depolamadaki nesnenin arama anahtarı. |
| `upload_id`  | Çok parçalı yüklemenin yükleme kimliği.    |

---

## Kimlik doğrulama ölçütleri {#authentication-metrics}

Kimlik doğrulama ile ilgili bir dizi ölçüt.

### `tuist_authentication_token_refresh_error_total` (sayaç) {#tuist_authentication_token_refresh_error_total-counter}

Toplam token yenileme hatası sayısı.

#### Etiketler {#tuist-authentication-token-refresh-error-total-tags}

| Etiket        | Açıklama                                                                            |
| ------------- | ----------------------------------------------------------------------------------- |
| `cli_version` | Hata ile karşılaşılan Tuist CLI sürümü.                                             |
| `neden`       | Token yenileme hatasının nedeni, örneğin `invalid_token_type` veya `invalid_token`. |

---

## Proje metrikleri {#projects-metrics}

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


## Veritabanı metrikleri {#database-metrics}

Veritabanı bağlantısıyla ilgili bir dizi ölçüm.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Veritabanı bağlantısına atanmak için kuyrukta bekleyen veritabanı sorgularının
sayısı.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Veritabanı sorgusuna atanmaya hazır veritabanı bağlantılarının sayısı.


### `tuist_repo_pool_db_connection_connected` (sayaç) {#tuist_repo_pool_db_connection_connected-counter}

Veritabanına kurulan bağlantıların sayısı.

### `tuist_repo_pool_db_connection_disconnected` (sayaç) {#tuist_repo_pool_db_connection_disconnected-counter}

Veritabanından bağlantısı kesilen bağlantıların sayısı.

## HTTP metrikleri {#http-metrics}

Tuist'in HTTP aracılığıyla diğer hizmetlerle etkileşimlerine ilişkin bir dizi
metrik.

### `tuist_http_request_count` (sayaç) {#tuist_http_request_count-last_value}

Giden HTTP isteklerinin sayısı.

### `tuist_http_request_duration_nanosecond_sum` (toplam) {#tuist_http_request_duration_nanosecond_sum-last_value}

Giden isteklerin süresinin toplamı (bağlantıya atanmak için bekledikleri süre
dahil).

### `tuist_http_request_duration_nanosecond_bucket` (dağıtım) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Giden isteklerin süresinin dağılımı (bağlantıya atanmak için bekledikleri süre
dahil).

### `tuist_http_queue_count` (sayaç) {#tuist_http_queue_count-counter}

Havuzdan alınan isteklerin sayısı.

### `tuist_http_queue_duration_nanoseconds_sum` (toplam) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantı almak için gereken süre.

### `tuist_http_queue_idle_time_nanoseconds_sum` (toplam) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Bağlantının geri alınmak için beklediği boşta kalma süresi.

### `tuist_http_queue_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantı almak için gereken süre.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dağıtım) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Bağlantının geri alınmak için beklediği boşta kalma süresi.

### `tuist_http_connection_count` (sayaç) {#tuist_http_connection_count-counter}

Kurulan bağlantıların sayısı.

### `tuist_http_connection_duration_nanoseconds_sum` (toplam) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Bir ana bilgisayara bağlantı kurmak için gereken süre.

### `tuist_http_connection_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Bir ana bilgisayara bağlantı kurmak için gereken sürenin dağılımı.

### `tuist_http_send_count` (sayaç) {#tuist_http_send_count-counter}

Havuzdan bir bağlantıya atandıktan sonra gönderilen isteklerin sayısı.

### `tuist_http_send_duration_nanoseconds_sum` (toplam) {#tuist_http_send_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen
süre.

### `tuist_http_send_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen
sürenin dağılımı.

### `tuist_http_receive_count` (sayaç) {#tuist_http_receive_count-counter}

Gönderilen isteklerden alınan yanıtların sayısı.

### `tuist_http_receive_duration_nanoseconds_sum` (toplam) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Yanıtları almak için harcanan süre.

### `tuist_http_receive_duration_nanoseconds_bucket` (dağıtım) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Yanıtları almak için harcanan sürenin dağılımı.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Kuyrukta kullanılabilir bağlantı sayısı.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Kullanılmakta olan kuyruk bağlantılarının sayısı.
