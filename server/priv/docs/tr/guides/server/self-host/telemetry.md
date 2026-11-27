---
{
  "title": "Telemetri",
  "titleTemplate": ":title | Kendi Sunucunuzda Barındırma | Sunucu | Kılavuzlar | Tuist",
  "description": "Prometheus metrikleri, OpenTelemetry izleri ve günlük yönlendirme ile Tuist sunucunuzu izleyin."
}
---
# Telemetri {#telemetry}

Tuist, birbirini tamamlayan üç gözlemlenebilirlik sinyali sunar: **metrikler** (Prometheus), **izler** (OpenTelemetry) ve **günlükler** (Loki uyumlu). Üçü de isteğe bağlıdır ve bağımsız olarak etkinleştirilebilir.

## Dağıtılmış izleme (OpenTelemetry) {#opentelemetry}

Tuist, dağıtılmış izleme için [OpenTelemetry](https://opentelemetry.io/) desteği sunar. Etkinleştirildiğinde sunucu; HTTP istekleri (Phoenix ve Bandit), veritabanı sorguları (Ecto), giden HTTP çağrıları (Finch) ve Broadway mesaj işleme için izler yayar. Bu izler sayesinde istek gecikmesini anlayabilir, yavaş sorguları tespit edebilir ve istekleri servisler arasında takip edebilirsiniz.

### Yapılandırma {#opentelemetry-configuration}

İz dışa aktarımını etkinleştirmek için aşağıdaki ortam değişkenini ayarlayın:

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | Bir OpenTelemetry Collector’ın gRPC uç noktası (ör. Grafana Alloy, Jaeger veya OTLP uyumlu herhangi bir toplayıcı) | Hayır | | `http://localhost:4317` |

Bu değişken ayarlanmadığında izleme devre dışı kalır ve ek yük oluşturmaz.

### Enstrümante edilen kütüphaneler {#opentelemetry-instrumented-libraries}

İzleme etkinleştirildiğinde aşağıdaki kütüphaneler otomatik olarak enstrümante edilir:

- **Bandit** – HTTP sunucu bağlantısı span’leri
- **Phoenix** – İstek yaşam döngüsü span’leri (denetleyici eylemleri, LiveView)
- **Ecto** – Sorgu meta verileri içeren veritabanı sorgusu span’leri
- **Finch** – Giden HTTP istemci isteği span’leri
- **Broadway** – Mesaj işleme ardışık düzeni span’leri

### Grafana Alloy ile örnek kurulum {#opentelemetry-alloy-example}

Toplayıcı olarak [Grafana Alloy](https://grafana.com/docs/alloy/latest/) kullanıyorsanız, OTLP izlerini alacak ve izleme arka ucunuza (ör. Grafana Cloud Tempo) iletecek şekilde yapılandırın:

```alloy
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  output {
    traces = [otelcol.exporter.otlp.your_backend.input]
  }
}
```

Ardından `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` değerini Alloy örneğini gösterecek şekilde ayarlayın, örn. `http://alloy:4317`.

## Günlük yönlendirme (Loki) {#log-forwarding}

Tuist, uygulama günlüklerini [Loki](https://grafana.com/oss/loki/) uyumlu bir uç noktaya iletebilir. Bu sayede günlüklerinizi metrikleriniz ve izlerinizle birlikte merkezileştirerek eksiksiz bir gözlemlenebilirlik resmi elde edersiniz. Günlükler Loki HTTP push API’si (`/loki/api/v1/push`) üzerinden gönderilir ve `app`, `env` ile `level` etiketlerini içerir.

### Yapılandırma {#log-forwarding-configuration}

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki uyumlu push API uç noktasının temel URL’si | Hayır | | `http://localhost:3100` |

Bu değişken ayarlanmadığında günlük yönlendirme devre dışı kalır.

### Grafana Alloy ile örnek kurulum {#log-forwarding-alloy-example}

Grafana Alloy, [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) bileşenini kullanarak yerel bir günlük aktarımcısı olarak çalışabilir:

```alloy
loki.source.api "default" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 3100
  }
  forward_to             = [loki.write.your_backend.receiver]
  use_incoming_timestamp = true
}

loki.write "your_backend" {
  endpoint {
    url = "https://your-loki-instance/loki/api/v1/push"
    basic_auth {
      username = "your-username"
      password = "your-password"
    }
  }
}
```

Ardından `TUIST_LOKI_URL=http://alloy:3100` ayarlayın.

Push API’sini sunuyorsa `TUIST_LOKI_URL` değerini doğrudan bir Loki örneğine de yönlendirebilirsiniz.

## Prometheus metrikleri {#prometheus-metrics}

Tuist sunucusunun topladığı metrikleri [Prometheus](https://prometheus.io/) ve [Grafana](https://grafana.com/) gibi bir görselleştirme aracıyla alarak ihtiyaçlarınıza uygun özel bir gösterge paneli oluşturabilirsiniz. Prometheus metrikleri 9091 portundaki `/metrics` uç noktası üzerinden sunulur. Prometheus’un [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) değeri 10_000 saniyeden az olacak şekilde ayarlanmalıdır (gözlemlenebilirlik ile metrik alma maliyetleri arasında denge kurmak için 30 saniye öneriyoruz).

## Gerçek kullanıcı izleme {#real-user-monitoring}

Tuist, pazarlama sitesi, belgeler ve gösterge panelinden tarayıcı performansını, sunulan JavaScript’e dahil edilen [Grafana Faro](https://grafana.com/oss/faro/) Web SDK’sını kullanarak raporlayabilir. Core Web Vitals’ı (en büyük içerikli boyama dahil), yakalanmamış hataları ve sayfa görüntülemelerini yakalar ve çalıştırdığınız bir [Faro alıcısına](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) gönderir — örneğin Loki ve Tempo’ya ileten Grafana Alloy’daki `faro.receiver` bileşeni.

### Yapılandırma {#real-user-monitoring-configuration}

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | Tarayıcının Faro yüklerini gönderdiği URL | Hayır | | `/-/faro` |

> [!NOTE]
> Gerçek kullanıcı izleme yalnızca `TUIST_FARO_COLLECTOR_URL` ayarlandığında etkinleşir. Bu olmadan hiçbir tarayıcı telemetrisi toplanmaz ve üçüncü taraf betiği yüklenmez.

`/-/faro` gibi aynı kaynaklı bir yol, çapraz kaynak isteklerini önler ve tarayıcının İçerik Güvenliği Politikasını değiştirmez. Giriş noktanız üzerinden Faro alıcınıza yönlendirin.

### Neler toplanır {#real-user-monitoring-collected}

- **Web vitals**: LCP, CLS, INP, FCP ve TTFB; tarayıcı tarafından otomatik olarak yakalanır
- **Sayfa görüntülemeleri**: yüklemede ve Phoenix LiveView gezinmesinde kaydedilir
- **Görünümler**: her yük, onu üreten bölümü taşır — `marketing`, `docs`, `dashboard` veya `api-docs`
- **Hatalar**: yakalanmamış istisnalar ve işlenmemiş promise reddetmeleri

### Gizlilik hususları {#real-user-monitoring-privacy}

- Kullanıcı kimliği eklenmez: yüklerde kullanıcı kimliği, e-posta veya hesap bilgisi bulunmaz
- Oturumlar ziyaretler arasında kalıcı değildir, bu nedenle tarayıcı depolamasına hiçbir şey yazılmaz
- Konsol yakalama kapalıdır, bu nedenle uygulama günlük çıktısı tarayıcıdan asla gönderilmez

## Elixir metrikleri {#elixir-metrics}

Varsayılan olarak Elixir çalışma zamanı, BEAM, Elixir ve kullandığımız bazı kütüphanelerin metriklerini dahil ederiz. Görmeyi bekleyebileceğiniz metriklerden bazıları şunlardır:

- [Uygulama](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Hangi metriklerin mevcut olduğunu ve bunların nasıl kullanılacağını öğrenmek için bu sayfaları kontrol etmenizi öneririz.

## Çalıştırma metrikleri {#runs-metrics}

Tuist Çalıştırmaları ile ilgili bir dizi metrik.

### `tuist_runs_total` (sayıcı) {#tuist_runs_total-counter}

Toplam Tuist Çalıştırma sayısı.

#### Etiketler {#tuist-runs-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `name` | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test` vb. |
| `is_ci` | Yürütücünün bir CI mı yoksa geliştiricinin makinesi mi olduğunu belirten bir boolean. |
| `status` | `success` durumunda `0`, `failure` durumunda `1`. |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Her tuist çalıştırmasının toplam süresi milisaniye cinsinden.

#### Etiketler {#tuist-runs-duration-miliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `name` | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test` vb. |
| `is_ci` | Yürütücünün bir CI mı yoksa geliştiricinin makinesi mi olduğunu belirten bir boolean. |
| `status` | `success` durumunda `0`, `failure` durumunda `1`. |

## Önbellek metrikleri {#cache-metrics}

Tuist Önbelleği ile ilgili bir dizi metrik.

### `tuist_cache_events_total` (sayıcı) {#tuist_cache_events_total-counter}

Toplam ikili önbellek olayı sayısı.

#### Etiketler {#tuist-cache-events-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `event_type` | `local_hit`, `remote_hit` veya `miss` olabilir. |

### `tuist_cache_uploads_total` (sayıcı) {#tuist_cache_uploads_total-counter}

İkili önbelleğe yapılan yükleme sayısı.

### `tuist_cache_uploaded_bytes` (toplam) {#tuist_cache_uploaded_bytes-sum}

İkili önbelleğe yüklenen bayt sayısı.

### `tuist_cache_downloads_total` (sayıcı) {#tuist_cache_downloads_total-counter}

İkili önbellekten yapılan indirme sayısı.

### `tuist_cache_downloaded_bytes` (toplam) {#tuist_cache_downloaded_bytes-sum}

İkili önbellekten indirilen bayt sayısı.

---

## Önizleme metrikleri {#previews-metrics}

Önizleme özelliği ile ilgili bir dizi metrik.

### `tuist_previews_uploads_total` (toplam) {#tuist_previews_uploads_total-counter}

Toplam yüklenen önizleme sayısı.

### `tuist_previews_downloads_total` (toplam) {#tuist_previews_downloads_total-counter}

Toplam indirilen önizleme sayısı.

---

## Depolama metrikleri {#storage-metrics}

Uzak depolamada (ör. s3) saklanan yapıtlarla ilgili bir dizi metrik.

> [!TIP]
> Bu metrikler, depolama işlemlerinin performansını anlamak ve olası darboğazları tespit etmek için kullanışlıdır.


### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Uzak depolamadan getirilen bir nesnenin boyutu (bayt cinsinden).

#### Etiketler {#tuist-storage-get-object-size-size-bytes-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Uzak depolamadan bir nesne boyutunun getirilme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_size_count` (sayıcı) {#tuist_storage_get_object_size_count-counter}

Uzak depolamadan bir nesne boyutunun kaç kez getirildiği.

#### Etiketler {#tuist-storage-get-object-size-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Uzak depolamadan tüm nesnelerin silinme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `project_slug` | Nesneleri silinen projenin proje kısaltması. |


### `tuist_storage_delete_all_objects_count` (sayıcı) {#tuist_storage_delete_all_objects_count-counter}

Uzak depolamadan tüm proje nesnelerinin kaç kez silindiği.

#### Etiketler {#tuist-storage-delete-all-objects-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `project_slug` | Nesneleri silinen projenin proje kısaltması. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Uzak depolamaya bir yüklemenin başlatılma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_multipart_start_upload_duration_count` (sayıcı) {#tuist_storage_multipart_start_upload_duration_count-counter}

Uzak depolamaya bir yüklemenin kaç kez başlatıldığı.

#### Etiketler {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Uzak depolamadan bir nesnenin dize olarak getirilme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_get_object_as_string_count` (sayı) {#tuist_storage_get_object_as_string_count-count}

Uzak depolamadan bir nesnenin dize olarak kaç kez getirildiği.

#### Etiketler {#tuist-storage-get-object-as-string-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Uzak depolamada bir nesnenin varlığının kontrol edilme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_check_object_existence_count` (sayı) {#tuist_storage_check_object_existence_count-count}

Uzak depolamada bir nesnenin varlığının kaç kez kontrol edildiği.

#### Etiketler {#tuist-storage-check-object-existence-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için indirme önceden imzalı URL’sinin oluşturulma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_generate_download_presigned_url_count` (sayı) {#tuist_storage_generate_download_presigned_url_count-count}

Uzak depolamadaki bir nesne için indirme önceden imzalı URL’sinin kaç kez oluşturulduğu.

#### Etiketler {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için parça yükleme önceden imzalı URL’sinin oluşturulma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (sayı) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Uzak depolamadaki bir nesne için parça yükleme önceden imzalı URL’sinin kaç kez oluşturulduğu.

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Uzak depolamaya bir yüklemenin tamamlanma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |


### `tuist_storage_multipart_complete_upload_count` (sayı) {#tuist_storage_multipart_complete_upload_count-count}

Uzak depolamaya bir yüklemenin toplam kaç kez tamamlandığı.

#### Etiketler {#tuist-storage-multipart-complete-upload-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

---

## Kimlik doğrulama ölçümleri {#authentication-metrics}

Kimlik doğrulamayla ilgili bir dizi ölçüm.

### `tuist_authentication_token_refresh_error_total` (sayıcı) {#tuist_authentication_token_refresh_error_total-counter}

Toplam jeton yenileme hatası sayısı.

#### Etiketler {#tuist-authentication-token-refresh-error-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `cli_version` | Hatayla karşılaşan Tuist CLI sürümü. |
| `reason` | Jeton yenileme hatasının nedeni, örneğin `invalid_token_type` veya `invalid_token`. |

---

## Projeler ölçümleri {#projects-metrics}

Projelerle ilgili bir dizi ölçüm.

### `tuist_projects_total` (son_değer) {#tuist_projects_total-last_value}

Toplam proje sayısı.

---

## Hesaplar ölçümleri {#accounts-metrics}

Hesaplarla (kullanıcılar ve organizasyonlar) ilgili bir dizi ölçüm.

### `tuist_accounts_organizations_total` (son_değer) {#tuist_accounts_organizations_total-last_value}

Toplam organizasyon sayısı.

### `tuist_accounts_users_total` (son_değer) {#tuist_accounts_users_total-last_value}

Toplam kullanıcı sayısı.


## Veritabanı ölçümleri {#database-metrics}

Veritabanı bağlantısıyla ilgili bir dizi ölçüm.

Repo havuzu ölçümleri dahili olarak her 100 ms’de bir örneklenir ve ardından Prometheus’a `/metrics` üzerinden sunulur. Aşağıdaki `last_value` ölçümleri, toplama zamanındaki en son havuz durumunu gösterir. Daha aşağıdaki basınç ölçümleri, bu 100 ms’lik örneklerden türetilen toplamlardır; bu sayede, bir sonraki toplamadan önce toparlansalar bile kısa doyum pencerelerini tespit etmek daha kolay olur.

### `tuist_repo_pool_checkout_queue_length` (son_değer) {#tuist_repo_pool_checkout_queue_length-last_value}

Bir veritabanı bağlantısına atanmayı bekleyen kuyruktaki veritabanı sorgularının sayısı.

#### Etiketler {#tuist_repo_pool_checkout_queue_length-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (son_değer) {#tuist_repo_pool_ready_conn_count-last_value}

Bir veritabanı sorgusuna atanmaya hazır olan veritabanı bağlantılarının sayısı.

#### Etiketler {#tuist_repo_pool_ready_conn_count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_size` (son_değer) {#tuist_repo_pool_size-last_value}

Havuzda yapılandırılan bağlantı sayısı.

#### Etiketler {#tuist_repo_pool_size-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

Alınan repo havuzu yoklama sayısının toplamı (her yoklamada 1 artar). Yoğunluk veya açlık yüzdelerini hesaplarken bunu payda olarak kullanın: `rate(busy_samples) / rate(total_samples)` veya `rate(starved_samples) / rate(total_samples)`.

#### Etiketler {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (toplam) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

Repo havuzu yoklamaları boyunca gözlemlenen kuyruktaki çekme isteklerinin toplamı. Bu, yalnızca en son kuyruk uzunluğu örneğinde görünmeyebilecek kısa süreli havuz çekişme patlamalarını tespit etmek için kullanışlıdır.

#### Etiketler {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

Kuyrukta en az bir veritabanı çekme isteğinin beklediği repo havuzu yoklama sayısı.

#### Etiketler {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

Çekme isteklerinin kuyruğa alındığı ve hazır bağlantı bulunmadığı repo havuzu yoklama sayısı. Burada sürekli bir artış genellikle havuzun doymuş olduğunu gösterir.

#### Etiketler {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Ölçümü üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (sayaç) {#tuist_repo_pool_db_connection_connected-counter}

Veritabanına kurulan bağlantı sayısı.

### `tuist_repo_pool_db_connection_disconnected` (sayaç) {#tuist_repo_pool_db_connection_disconnected-counter}

Veritabanından koparılan bağlantı sayısı.

#### Etiketler {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| Etiket | Açıklama |
|--- | ---- |
| `tag` | Üreten depoyu tanımlayan DBConnection dinleyici etiketi. |

## HTTP ölçümleri {#http-metrics}

Tuist’in diğer hizmetlerle HTTP üzerinden etkileşimleriyle ilgili bir dizi ölçüm.

### `tuist_http_request_count` (sayaç) {#tuist_http_request_count-last_value}

Giden HTTP isteklerinin sayısı.

### `tuist_http_request_duration_nanoseconds_sum` (toplam) {#tuist_http_request_duration_nanoseconds_sum-last_value}

Giden isteklerin süresinin toplamı (bir bağlantıya atanmayı bekledikleri süre dahil).

### `tuist_http_request_duration_nanoseconds_bucket` (dağılım) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
Giden isteklerin süresinin dağılımı (bir bağlantıya atanmayı bekledikleri süre dahil).

### `tuist_http_queue_count` (sayaç) {#tuist_http_queue_count-counter}

Havuzdan alınan istek sayısı.

### `tuist_http_queue_duration_nanoseconds_sum` (toplam) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantı almanın sürdüğü süre.

### `tuist_http_queue_idle_time_nanoseconds_sum` (toplam) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_queue_duration_nanoseconds_bucket` (dağılım) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantı almanın sürdüğü süre.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dağılım) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_connection_count` (sayaç) {#tuist_http_connection_count-counter}

Kurulan bağlantı sayısı.

### `tuist_http_connection_duration_nanoseconds_sum` (toplam) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Bir ana bilgisayarla bağlantı kurmanın sürdüğü süre.

### `tuist_http_connection_duration_nanoseconds_bucket` (dağılım) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Bir ana bilgisayarla bağlantı kurma süresinin dağılımı.

### `tuist_http_send_count` (sayaç) {#tuist_http_send_count-counter}

Havuzdan bir bağlantıya atandıktan sonra gönderilen istek sayısı.

### `tuist_http_send_duration_nanoseconds_sum` (toplam) {#tuist_http_send_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanmasının sürdüğü süre.

### `tuist_http_send_duration_nanoseconds_bucket` (dağılım) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanma süresinin dağılımı.

### `tuist_http_receive_count` (sayaç) {#tuist_http_receive_count-counter}

Gönderilen isteklerden alınan yanıt sayısı.

### `tuist_http_receive_duration_nanoseconds_sum` (toplam) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Yanıtların alınması için harcanan süre.

### `tuist_http_receive_duration_nanoseconds_bucket` (dağılım) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Yanıtların alınması için harcanan sürenin dağılımı.

### `tuist_http_queue_available_connections` (son_değer) {#tuist_http_queue_available_connections-last_value}

Kuyrukta kullanılabilir olan bağlantı sayısı.

### `tuist_http_queue_in_use_connections` (son_değer) {#tuist_http_queue_in_use_connections-last_value}

Kullanımda olan kuyruk bağlantısı sayısı.
