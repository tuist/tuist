---
{
  "title": "Telemetri",
  "titleTemplate": ":title | Kendi Sunucunuzda Barındırma | Sunucu | Kılavuzlar | Tuist",
  "description": "Tuist sunucunuzu Prometheus metrikleri, OpenTelemetry izleri ve günlük yönlendirme ile izleyin."
}
---
# Telemetri {#telemetry}

Tuist üç tamamlayıcı gözlemlenebilirlik sinyali sunar: **metrikler** (Prometheus), **izler** (OpenTelemetry) ve **loglar** (Loki uyumlu). Üçü de isteğe bağlıdır ve bağımsız olarak etkinleştirilebilir.

## Dağıtılmış izleme (OpenTelemetry) {#opentelemetry}

Tuist, dağıtılmış izleme için [OpenTelemetry](https://opentelemetry.io/) desteği sunar. Etkinleştirildiğinde sunucu; HTTP istekleri (Phoenix ve Bandit), veritabanı sorguları (Ecto), giden HTTP çağrıları (Finch) ve Broadway mesaj işleme için izler yayar. Bu izler, istek gecikmesini anlamanıza, yavaş sorguları belirlemenize ve istekleri servisler arasında takip etmenize olanak tanır.

### Yapılandırma {#opentelemetry-configuration}

İz dışa aktarımını etkinleştirmek için aşağıdaki ortam değişkenini ayarlayın:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | Bir OpenTelemetry Collector’ın gRPC uç noktası (ör. Grafana Alloy, Jaeger veya OTLP uyumlu herhangi bir toplayıcı) | Hayır | | `http://localhost:4317` |

Bu değişken ayarlanmadığında izleme devre dışı kalır ve ek yük oluşturmaz.

### Enstrümante edilen kütüphaneler {#opentelemetry-instrumented-libraries}

İzleme etkinleştirildiğinde aşağıdaki kütüphaneler otomatik olarak enstrümante edilir:

- **Bandit** -- HTTP sunucu bağlantısı span’leri
- **Phoenix** -- İstek yaşam döngüsü span’leri (denetleyici eylemleri, LiveView)
- **Ecto** -- Sorgu meta verileri içeren veritabanı sorgusu span’leri
- **Finch** -- Giden HTTP istemci isteği span’leri
- **Broadway** -- Mesaj işleme hattı span’leri

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

Ardından `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` değerini Alloy örneğine işaret edecek şekilde ayarlayın, örn. `http://alloy:4317`.

## Log yönlendirme (Loki) {#log-forwarding}

Tuist, uygulama loglarını [Loki](https://grafana.com/oss/loki/) uyumlu bir uç noktaya iletebilir. Bu, metrikleriniz ve izlerinizle birlikte logları merkezileştirerek eksiksiz bir gözlemlenebilirlik görünümü elde etmenizi sağlar. Loglar Loki HTTP push API’si (`/loki/api/v1/push`) üzerinden gönderilir ve `app`, `env` ile `level` etiketlerini içerir.

### Yapılandırma {#log-forwarding-configuration}

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki uyumlu push API uç noktasının temel URL’si | Hayır | | `http://localhost:3100` |

Bu değişken ayarlanmadığında log yönlendirme devre dışı kalır.

### Grafana Alloy ile örnek kurulum {#log-forwarding-alloy-example}

Grafana Alloy, [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) bileşenini kullanarak yerel bir log aktarımcısı olarak çalışabilir:

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

Push API’sini sunuyorsa `TUIST_LOKI_URL` doğrudan bir Loki örneğine de işaret edebilirsiniz.

## Prometheus metrikleri {#prometheus-metrics}

Tuist sunucusu tarafından toplanan metrikleri [Prometheus](https://prometheus.io/) ve [Grafana](https://grafana.com/) gibi bir görselleştirme aracı kullanarak içe aktarabilir, ihtiyaçlarınıza özel bir kontrol paneli oluşturabilirsiniz. Prometheus metrikleri 9091 portundaki `/metrics` uç noktası üzerinden sunulur. Prometheus'un [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) değeri 10_000 saniyeden az olacak şekilde ayarlanmalıdır (gözlemlenebilirlik ile metrik içe aktarma maliyetleri arasında denge kurmak için 30 saniye önerilir).

## Gerçek kullanıcı izleme {#real-user-monitoring}

Tuist, pazarlama sitesi, belgeler ve kontrol panelindeki tarayıcı performansını, sunulan JavaScript'e dahil edilen [Grafana Faro](https://grafana.com/oss/faro/) Web SDK'sını kullanarak raporlayabilir. Core Web Vitals (en büyük içerikli boyama dahil), yakalanmamış hataları ve sayfa görüntülemelerini yakalar ve bunları çalıştırdığınız bir [Faro alıcısına](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/) gönderir — örneğin Loki ve Tempo'ya ileten Grafana Alloy'deki `faro.receiver` bileşeni.

### Yapılandırma {#real-user-monitoring-configuration}

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | Tarayıcının Faro yüklerini gönderdiği URL | Hayır | | `/-/faro` |

> [!NOTE]
> Gerçek kullanıcı izleme yalnızca `TUIST_FARO_COLLECTOR_URL` ayarlandığında etkinleştirilir. Bu ayar olmadan hiçbir tarayıcı telemetrisi toplanmaz ve üçüncü taraf komut dosyası yüklenmez.

`/-/faro` gibi aynı kaynaklı bir yol, çapraz kaynak isteklerini önler ve tarayıcının İçerik Güvenliği Politikasını değiştirmez. Giriş noktanız üzerinden Faro alıcınıza işaret edin.

### Neler toplanır {#real-user-monitoring-collected}

- **Web vitals**: LCP, CLS, INP, FCP ve TTFB, tarayıcı tarafından otomatik olarak yakalanır
- **Sayfa görüntülemeleri**: yükleme sırasında ve Phoenix LiveView gezinmesinde kaydedilir
- **Görünümler**: her yük, onu üreten bölümü taşır — `marketing`, `docs`, `dashboard` veya `api-docs`
- **Hatalar**: yakalanmamış istisnalar ve işlenmemiş promise reddetmeleri

### Gizlilik hususları {#real-user-monitoring-privacy}

- Kullanıcı kimliği eklenmez: yüklerde kullanıcı kimliği, e-posta veya hesap bilgisi bulunmaz
- Oturumlar ziyaretler arasında kalıcı değildir, bu nedenle tarayıcı depolamasına hiçbir şey yazılmaz
- Konsol yakalama kapalıdır, bu nedenle uygulama log çıktısı asla tarayıcıdan gönderilmez

## Elixir metrikleri {#elixir-metrics}

Varsayılan olarak Elixir çalışma zamanı, BEAM, Elixir ve kullandığımız bazı kütüphanelerin metriklerini dahil ederiz. Görmeyi bekleyebileceğiniz metriklerden bazıları şunlardır:

- [Uygulama](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Hangi metriklerin mevcut olduğunu ve nasıl kullanılacağını öğrenmek için bu sayfaları kontrol etmenizi öneririz.

## Çalıştırma metrikleri {#runs-metrics}

Tuist Çalıştırmaları ile ilgili bir dizi metrik.

### `tuist_runs_total` (sayaç) {#tuist_runs_total-counter}

Toplam Tuist Çalıştırma sayısı.

#### Etiketler {#tuist-runs-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `name` | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test` vb. |
| `is_ci` | Yürütücünün bir CI mı yoksa geliştiricinin makinesi mi olduğunu belirten bir boolean değer. |
| `status` | `success` durumunda `0`, `failure` durumunda `1`. |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Her tuist çalıştırmasının toplam süresi milisaniye cinsinden.

#### Etiketler {#tuist-runs-duration-miliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `name` | Çalıştırılan `tuist` komutunun adı, örneğin `build`, `test` vb. |
| `is_ci` | Yürütücünün bir CI mı yoksa geliştiricinin makinesi mi olduğunu belirten bir boolean değer. |
| `status` | `success` durumunda `0`, `failure` durumunda `1`. |

## Önbellek metrikleri {#cache-metrics}

Tuist Önbelleği ile ilgili bir dizi metrik.

### `tuist_cache_events_total` (sayaç) {#tuist_cache_events_total-counter}

Toplam ikili önbellek olayı sayısı.

#### Etiketler {#tuist-cache-events-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `event_type` | `local_hit`, `remote_hit` veya `miss` olabilir. |

### `tuist_cache_uploads_total` (sayaç) {#tuist_cache_uploads_total-counter}

İkili önbelleğe yapılan yükleme sayısı.

### `tuist_cache_uploaded_bytes` (toplam) {#tuist_cache_uploaded_bytes-sum}

İkili önbelleğe yüklenen bayt sayısı.

### `tuist_cache_downloads_total` (sayaç) {#tuist_cache_downloads_total-counter}

İkili önbellekten yapılan indirme sayısı.

### `tuist_cache_downloaded_bytes` (toplam) {#tuist_cache_downloaded_bytes-sum}

İkili önbellekten indirilen bayt sayısı.

---

## Önizleme metrikleri {#previews-metrics}

Önizleme özelliği ile ilgili bir dizi metrik.

### `tuist_previews_uploads_total` (toplam) {#tuist_previews_uploads_total-counter}

Yüklenen toplam önizleme sayısı.

### `tuist_previews_downloads_total` (toplam) {#tuist_previews_downloads_total-counter}

İndirilen toplam önizleme sayısı.

---

## Depolama metrikleri {#storage-metrics}

Uzak depolamada (ör. s3) saklanan yapıtlarla ilgili bir dizi metrik.

> [!TIP]
> Bu metrikler, depolama işlemlerinin performansını anlamak ve olası darboğazları tespit etmek için faydalıdır.


### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Uzak depolamadan alınan bir nesnenin boyutu (bayt cinsinden).

#### Etiketler {#tuist-storage-get-object-size-size-bytes-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Uzak depolamadan bir nesne boyutunu getirme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_size_count` (sayaç) {#tuist_storage_get_object_size_count-counter}

Uzak depolamadan bir nesne boyutunun getirilme sayısı.

#### Etiketler {#tuist-storage-get-object-size-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Uzak depolamadan tüm nesneleri silme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `project_slug` | Nesneleri silinen projenin proje slug'ı. |


### `tuist_storage_delete_all_objects_count` (sayaç) {#tuist_storage_delete_all_objects_count-counter}

Tüm proje nesnelerinin uzak depolamadan silinme sayısı.

#### Etiketler {#tuist-storage-delete-all-objects-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `project_slug` | Nesneleri silinen projenin proje slug'ı. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Uzak depolamaya bir yüklemeyi başlatma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_multipart_start_upload_duration_count` (sayaç) {#tuist_storage_multipart_start_upload_duration_count-counter}

Uzak depolamaya bir yüklemenin başlatılma sayısı.

#### Etiketler {#tuist-storage-multipart-start-upload-duration-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Uzak depolamadan bir nesneyi dize olarak getirme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_get_object_as_string_count` (sayı) {#tuist_storage_get_object_as_string_count-count}

Uzak depolamadan bir nesnenin dize olarak getirilme sayısı.

#### Etiketler {#tuist-storage-get-object-as-string-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Uzak depolamada bir nesnenin varlığını kontrol etme süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_check_object_existence_count` (sayı) {#tuist_storage_check_object_existence_count-count}

Uzak depolamada bir nesnenin varlığının kontrol edilme sayısı.

#### Etiketler {#tuist-storage-check-object-existence-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için indirme önceden imzalı URL oluşturma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |


### `tuist_storage_generate_download_presigned_url_count` (sayı) {#tuist_storage_generate_download_presigned_url_count-count}

Uzak depolamadaki bir nesne için indirme önceden imzalı URL oluşturulma sayısı.

#### Etiketler {#tuist-storage-generate-download-presigned-url-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Uzak depolamadaki bir nesne için parça yükleme önceden imzalı URL oluşturma süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (sayı) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Uzak depolamadaki bir nesne için parça yükleme önceden imzalı URL oluşturulma sayısı.

#### Etiketler {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `part_number` | Yüklenen nesnenin parça numarası. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Uzak depolamaya bir yüklemeyi tamamlama süresi (milisaniye cinsinden).

#### Etiketler {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |


### `tuist_storage_multipart_complete_upload_count` (sayı) {#tuist_storage_multipart_complete_upload_count-count}

Uzak depolamaya bir yüklemenin tamamlanma toplam sayısı.

#### Etiketler {#tuist-storage-multipart-complete-upload-count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `object_key` | Nesnenin uzak depolamadaki arama anahtarı. |
| `upload_id` | Çok parçalı yüklemenin yükleme kimliği. |

---

## Kimlik doğrulama metrikleri {#authentication-metrics}

Kimlik doğrulama ile ilgili metrik kümesi.

### `tuist_authentication_token_refresh_error_total` (sayaç) {#tuist_authentication_token_refresh_error_total-counter}

Token yenileme hatalarının toplam sayısı.

#### Etiketler {#tuist-authentication-token-refresh-error-total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `cli_version` | Hatayla karşılaşan Tuist CLI sürümü. |
| `reason` | Token yenileme hatasının nedeni, örneğin `invalid_token_type` veya `invalid_token`. |

---

## Projeler metrikleri {#projects-metrics}

Projelerle ilgili metrik kümesi.

### `tuist_projects_total` (son_değer) {#tuist_projects_total-last_value}

Projelerin toplam sayısı.

---

## Hesaplar metrikleri {#accounts-metrics}

Hesaplarla (kullanıcılar ve organizasyonlar) ilgili metrik kümesi.

### `tuist_accounts_organizations_total` (son_değer) {#tuist_accounts_organizations_total-last_value}

Organizasyonların toplam sayısı.

### `tuist_accounts_users_total` (son_değer) {#tuist_accounts_users_total-last_value}

Kullanıcıların toplam sayısı.


## Veritabanı metrikleri {#database-metrics}

Veritabanı bağlantısıyla ilgili metrik kümesi.

Repo havuzu metrikleri dahili olarak her 100 ms'de bir örneklenir ve ardından Prometheus'a `/metrics` üzerinden sunulur. Aşağıdaki `last_value` metrikleri, toplama zamanındaki en son havuz durumunu gösterir. Daha aşağıdaki basınç metrikleri, bu 100 ms'lik örneklerden türetilen toplamlardır; bu sayede, bir sonraki toplamadan önce toparlansalar bile kısa süreli doygunluk pencerelerini tespit etmek daha kolay olur.

### `tuist_repo_pool_checkout_queue_length` (son_değer) {#tuist_repo_pool_checkout_queue_length-last_value}

Bir veritabanı bağlantısına atanmayı bekleyen kuyruktaki veritabanı sorgularının sayısı.

#### Etiketler {#tuist_repo_pool_checkout_queue_length-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (son_değer) {#tuist_repo_pool_ready_conn_count-last_value}

Bir veritabanı sorgusuna atanmaya hazır olan veritabanı bağlantılarının sayısı.

#### Etiketler {#tuist_repo_pool_ready_conn_count-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_size` (son_değer) {#tuist_repo_pool_size-last_value}

Havuzda yapılandırılan bağlantı sayısı.

#### Etiketler {#tuist_repo_pool_size-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

Alınan repo havuzu yoklama sayısının toplamı (her yoklamada 1 artar). Yoğunluk veya açlık yüzdelerini hesaplarken bunu payda olarak kullanın: `rate(busy_samples) / rate(total_samples)` veya `rate(starved_samples) / rate(total_samples)`.

#### Etiketler {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (toplam) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

Repo havuzu yoklamaları boyunca gözlemlenen kuyruktaki checkout isteklerinin toplamı. Bu, yalnızca en son kuyruk uzunluğu örneğinde görünmeyebilecek kısa süreli havuz çekişme patlamalarını tespit etmek için kullanışlıdır.

#### Etiketler {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

En az bir veritabanı checkout isteğinin kuyrukta beklediği repo havuzu yoklama sayısı.

#### Etiketler {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (toplam) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

Checkout isteklerinin kuyruğa alındığı ve hazır bağlantı bulunmadığı repo havuzu yoklama sayısı. Burada sürekli bir artış genellikle havuzun doymuş olduğunu gösterir.

#### Etiketler {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| Etiket | Açıklama |
|--- | ---- |
| `repo` | Metriği üreten depo, örneğin `postgres`, `clickhouse_read` veya `clickhouse_write`. |
| `database` | Destekleyici veritabanı türü, örneğin `postgres` veya `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (sayaç) {#tuist_repo_pool_db_connection_connected-counter}

Veritabanına kurulan bağlantı sayısı.

### `tuist_repo_pool_db_connection_disconnected` (sayaç) {#tuist_repo_pool_db_connection_disconnected-counter}

Veritabanından kesilen bağlantı sayısı.

#### Etiketler {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| Etiket | Açıklama |
|--- | ---- |
| `tag` | Yayınlayan depoyu tanımlayan DBConnection dinleyici etiketi. |

## HTTP metrikleri {#http-metrics}

Tuist'in diğer hizmetlerle HTTP üzerinden etkileşimleriyle ilgili metrik kümesi.

### `tuist_http_request_count` (sayaç) {#tuist_http_request_count-last_value}

Giden HTTP isteklerinin sayısı.

### `tuist_http_request_duration_nanoseconds_sum` (toplam) {#tuist_http_request_duration_nanoseconds_sum-last_value}

Giden isteklerin sürelerinin toplamı (bir bağlantıya atanmayı bekledikleri süre dahil).

### `tuist_http_request_duration_nanoseconds_bucket` (dağılım) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
Giden isteklerin sürelerinin dağılımı (bir bağlantıya atanmayı bekledikleri süre dahil).

### `tuist_http_queue_count` (sayaç) {#tuist_http_queue_count-counter}

Havuzdan alınan istek sayısı.

### `tuist_http_queue_duration_nanoseconds_sum` (toplam) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantı almak için geçen süre.

### `tuist_http_queue_idle_time_nanoseconds_sum` (toplam) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_queue_duration_nanoseconds_bucket` (dağılım) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantı almak için geçen süre.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dağılım) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Bir bağlantının alınmayı beklerken boşta kaldığı süre.

### `tuist_http_connection_count` (sayaç) {#tuist_http_connection_count-counter}

Kurulan bağlantı sayısı.

### `tuist_http_connection_duration_nanoseconds_sum` (toplam) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Bir ana bilgisayarla bağlantı kurmak için geçen süre.

### `tuist_http_connection_duration_nanoseconds_bucket` (dağılım) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Bir ana bilgisayarla bağlantı kurmak için geçen sürenin dağılımı.

### `tuist_http_send_count` (sayaç) {#tuist_http_send_count-counter}

Havuzdan bir bağlantıya atandıktan sonra gönderilen istek sayısı.

### `tuist_http_send_duration_nanoseconds_sum` (toplam) {#tuist_http_send_duration_nanoseconds_sum-sum}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen süre.

### `tuist_http_send_duration_nanoseconds_bucket` (dağılım) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Havuzdan bir bağlantıya atandıktan sonra isteklerin tamamlanması için geçen sürenin dağılımı.

### `tuist_http_receive_count` (sayaç) {#tuist_http_receive_count-counter}

Gönderilen isteklerden alınan yanıt sayısı.

### `tuist_http_receive_duration_nanoseconds_sum` (toplam) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Yanıtları almak için harcanan süre.

### `tuist_http_receive_duration_nanoseconds_bucket` (dağılım) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Yanıtları almak için harcanan sürenin dağılımı.

### `tuist_http_queue_available_connections` (son_değer) {#tuist_http_queue_available_connections-last_value}

Kuyrukta kullanılabilir olan bağlantı sayısı.

### `tuist_http_queue_in_use_connections` (son_değer) {#tuist_http_queue_in_use_connections-last_value}

Kullanımda olan kuyruk bağlantısı sayısı.
