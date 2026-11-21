---
{
  "title": "ტელემეტრია",
  "titleTemplate": ":title | საკუთარ სერვერზე განთავსება | სერვერი | სახელმძღვანელოები | Tuist",
  "description": "აკონტროლეთ თქვენი Tuist სერვერი Prometheus მეტრიკებით, OpenTelemetry ტრეისებით და ლოგების გადამისამართებით."
}
---
# ტელემეტრია {#telemetry}

Tuist გთავაზობთ სამ დამატებით დაკვირვების სიგნალს: **მეტრიკები** (Prometheus), **ტრეისინგი** (OpenTelemetry) და **ლოგები** (Loki-თან თავსებადი). სამივე არის არასავალდებულო და შეიძლება ჩაირთოს დამოუკიდებლად.

## განაწილებული ტრეისინგი (OpenTelemetry) {#opentelemetry}

Tuist მხარდაჭერას უწევს [OpenTelemetry](https://opentelemetry.io/)-ს განაწილებული ტრეისინგისთვის. ჩართვისას, სერვერი აგენერირებს ტრეისებს HTTP მოთხოვნებისთვის (Phoenix და Bandit), მონაცემთა ბაზის ქვეითებებისთვის (Ecto), გამავალი HTTP გამოძახებებისთვის (Finch) და Broadway შეტყობინებების დამუშავებისთვის. ეს ტრეისები გაძლევთ შესაძლებლობას გაიგოთ მოთხოვნის ლატენტურობა, იდენტიფიცირება მოახდინოთ ნელი ქვეითებების და მიჰყვეთ მოთხოვნებს სერვისებს შორის.

### კონფიგურაცია {#opentelemetry-configuration}

ტრეისების ექსპორტის ჩასართავად დააყენეთ შემდეგი გარემოს ცვლადი:

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector-ის gRPC წერტილი (მაგ. Grafana Alloy, Jaeger, ან ნებისმიერი OTLP-თან თავსებადი კოლექტორი) | არა | | `http://localhost:4317` |

როდესაც ეს ცვლადი არ არის დაყენებული, ტრეისინგი გამორთულია და არ ქმნის დამატებით დატვირთვას.

### ინსტრუმენტირებული ბიბლიოთეკები {#opentelemetry-instrumented-libraries}

ტრეისინგის ჩართვისას შემდეგი ბიბლიოთეკები ავტომატურად ინსტრუმენტირდება:

- **Bandit** — HTTP სერვერის კავშირის სპანები
- **Phoenix** — მოთხოვნის სასიცოცხლო ციკლის სპანები (კონტროლერის ქმედებები, LiveView)
- **Ecto** — მონაცემთა ბაზის ქვეითებების სპანები მეტამონაცემებით
- **Finch** — გამავალი HTTP კლიენტის მოთხოვნის სპანები
- **Broadway** — შეტყობინებების დამუშავების პაიპლაინის სპანები

### მაგალითი Grafana Alloy-ით {#opentelemetry-alloy-example}

თუ თქვენ იყენებთ [Grafana Alloy](https://grafana.com/docs/alloy/latest/)-ს როგორც კოლექტორს, დააკონფიგურირეთ ის OTLP ტრეისების მიღებისა და თქვენს ტრეისინგის ბექენდზე გადაგზავნისთვის (მაგ. Grafana Cloud Tempo):

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

შემდეგ დააყენეთ `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT`, რათა მიუთითოთ Alloy ინსტანციაზე, მაგ. `http://alloy:4317`.

## ლოგების გადამისამართება (Loki) {#log-forwarding}

Tuist-ს შეუძლია აპლიკაციის ლოგების გადამისამართება [Loki](https://grafana.com/oss/loki/)-თან თავსებად წერტილზე. ეს საშუალებას გაძლევთ გააერთიანოთ ლოგები თქვენს მეტრიკებთან და ტრეისებთან ერთად სრული დაკვირვების სურათისთვის. ლოგები იგზავნება Loki HTTP push API-ის (`/loki/api/v1/push`) საშუალებით და შეიცავს ლეიბლებს `app`, `env` და `level`-ისთვის.

### კონფიგურაცია {#log-forwarding-configuration}

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki-თან თავსებადი push API წერტილის საბაზისო URL | არა | | `http://localhost:3100` |

როდესაც ეს ცვლადი არ არის დაყენებული, ლოგების გადამისამართება გამორთულია.

### მაგალითი Grafana Alloy-ით {#log-forwarding-alloy-example}

Grafana Alloy-ს შეუძლია იმოქმედოს როგორც ლოკალურმა ლოგების რელემ, მისი [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) კომპონენტის გამოყენებით:

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

შემდეგ დააყენეთ `TUIST_LOKI_URL=http://alloy:3100`.

ასევე შეგიძლიათ `TUIST_LOKI_URL` პირდაპირ მიუთითოთ Loki ინსტანციაზე, თუ ის ხელმისაწვდომს ხდის push API-ს.

## Prometheus მეტრიკები {#prometheus-metrics}

შეგიძლიათ შეიყვანოთ Tuist სერვერის მიერ შეგროვებული მეტრიკები [Prometheus](https://prometheus.io/)-ისა და ვიზუალიზაციის ინსტრუმენტის, მაგალითად [Grafana](https://grafana.com/)-ის გამოყენებით, რათა შექმნათ თქვენს საჭიროებებზე მორგებული პერსონალური დაფა. Prometheus-ის მეტრიკები ხელმისაწვდომია `/metrics` წერტილზე, პორტ 9091-ზე. Prometheus-ის [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) უნდა იყოს დაყენებული 10_000 წამზე ნაკლებად (ჩვენ გირჩევთ 30 წამს, რათა დაბალანსდეს დაკვირვება მეტრიკების შეგროვების ხარჯებთან).

## რეალური მომხმარებლის მონიტორინგი {#real-user-monitoring}

Tuist-ს შეუძლია ანგარიში გაუწიოს ბრაუზერის შესრულებას მარკეტინგული საიტიდან, დოკუმენტაციიდან და დაფიდან [Grafana Faro](https://grafana.com/oss/faro/) Web SDK-ის გამოყენებით, რომელიც ჩართულია მიწოდებულ JavaScript-ში. ის აღრიცხავს ძირითად ვებ-ვიტალებს (მათ შორის Largest Contentful Paint), დაუჭერელ შეცდომებს და გვერდის ნახვებს, და აგზავნის მათ თქვენს მიერ გაშვებულ [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/)-ზე — მაგალითად, `faro.receiver` კომპონენტზე Grafana Alloy-ში, რომელიც გადაამისამართებს Loki-სა და Tempo-ში.

### კონფიგურაცია {#real-user-monitoring-configuration}

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | URL, რომელზეც ბრაუზერი აგზავნის Faro პეილოადებს | არა | | `/-/faro` |

> [!NOTE]
> რეალური მომხმარებლის მონიტორინგი ჩართულია მხოლოდ მაშინ, როდესაც `TUIST_FARO_COLLECTOR_URL` არის დაყენებული. მის გარეშე, ბრაუზერის ტელემეტრია არ იკრიბება და მესამე მხარის სკრიპტი არ იტვირთება.

იგივე წყაროს გზა, როგორიცაა `/-/faro`, თავს არიდებს ჯვარედინ წყაროს მოთხოვნებს და ინარჩუნებს ბრაუზერის შინაარსის უსაფრთხოების პოლიტიკას უცვლელად. მიუთითეთ ის თქვენს Faro მიმღებზე თქვენი ingress-ის საშუალებით.

### რა იკრიბება {#real-user-monitoring-collected}

- **ვებ-ვიტალები**: LCP, CLS, INP, FCP და TTFB, რომლებიც ავტომატურად ფიქსირდება ბრაუზერის მიერ
- **გვერდის ნახვები**: ფიქსირდება ჩატვირთვისას და Phoenix LiveView ნავიგაციისას
- **ნახვები**: თითოეული პეილოადი შეიცავს იმ სექციას, რომელმაც ის წარმოქმნა — `marketing`, `docs`, `dashboard` ან `api-docs`
- **შეცდომები**: დაუჭერელი გამონაკლისები და დაუმუშავებელი promise უარყოფები

### კონფიდენციალურობის მოსაზრებები {#real-user-monitoring-privacy}

- მომხმარებლის იდენტობა არ არის მიბმული: პეილოადები არ შეიცავს მომხმარებლის ID-ს, ელფოსტას ან ანგარიშს
- სესიები არ ინახება ვიზიტებს შორის, ამიტომ არაფერი იწერება ბრაუზერის საცავში
- კონსოლის ჩაჭრა გამორთულია, ამიტომ აპლიკაციის ლოგების გამოტანა არასდროს იგზავნება ბრაუზერიდან

## Elixir მეტრიკები {#elixir-metrics}

ნაგულისხმევად ჩვენ ვრთავთ Elixir runtime-ის, BEAM-ის, Elixir-ის და ჩვენს მიერ გამოყენებული ზოგიერთი ბიბლიოთეკის მეტრიკებს. ქვემოთ მოცემულია ზოგიერთი მეტრიკა, რომლის ნახვაც შეგიძლიათ:

- [Application](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

ჩვენ გირჩევთ შეამოწმოთ ეს გვერდები, რათა გაიგოთ, რომელი მეტრიკებია ხელმისაწვდომი და როგორ გამოიყენოთ ისინი.

## Runs მეტრიკები {#runs-metrics}

მეტრიკების ნაკრები, დაკავშირებული Tuist Runs-თან.

### `tuist_runs_total` (მრიცხველი) {#tuist_runs_total-counter}

Tuist Runs-ის საერთო რაოდენობა.

#### ტეგები {#tuist-runs-total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც შესრულდა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულიანი მნიშვნელობა, რომელიც მიუთითებს, იყო შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `0` `success`-ის შემთხვევაში, `1` `failure`-ის შემთხვევაში. |

### `tuist_runs_duration_milliseconds` (ჰისტოგრამა) {#tuist_runs_duration_milliseconds-histogram}

თითოეული tuist გაშვების საერთო ხანგრძლივობა მილიწამებში.

#### ტეგები {#tuist-runs-duration-miliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც შესრულდა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულიანი მნიშვნელობა, რომელიც მიუთითებს, იყო შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `0` `success`-ის შემთხვევაში, `1` `failure`-ის შემთხვევაში. |

## Cache მეტრიკები {#cache-metrics}

მეტრიკების ნაკრები, დაკავშირებული Tuist Cache-თან.

### `tuist_cache_events_total` (მრიცხველი) {#tuist_cache_events_total-counter}

ბინარული cache მოვლენების საერთო რაოდენობა.

#### ტეგები {#tuist-cache-events-total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `event_type` | შეიძლება იყოს `local_hit`, `remote_hit` ან `miss`. |

### `tuist_cache_uploads_total` (მრიცხველი) {#tuist_cache_uploads_total-counter}

ატვირთვების რაოდენობა ბინარულ cache-ში.

### `tuist_cache_uploaded_bytes` (ჯამი) {#tuist_cache_uploaded_bytes-sum}

ბიტების რაოდენობა, ატვირთული ბინარულ cache-ში.

### `tuist_cache_downloads_total` (მრიცხველი) {#tuist_cache_downloads_total-counter}

ჩამოტვირთვების რაოდენობა ბინარული cache-დან.

### `tuist_cache_downloaded_bytes` (ჯამი) {#tuist_cache_downloaded_bytes-sum}

ბიტების რაოდენობა, ჩამოტვირთული ბინარული cache-დან.

---

## Previews მეტრიკები {#previews-metrics}

მეტრიკების ნაკრები, დაკავშირებული previews ფუნქციასთან.

### `tuist_previews_uploads_total` (ჯამი) {#tuist_previews_uploads_total-counter}

ატვირთული previews-ების საერთო რაოდენობა.

### `tuist_previews_downloads_total` (ჯამი) {#tuist_previews_downloads_total-counter}

ჩამოტვირთული previews-ების საერთო რაოდენობა.

---

## Storage მეტრიკები {#storage-metrics}

მეტრიკების ნაკრები, დაკავშირებული არტიფაქტების შენახვასთან შორეულ საცავში (მაგ. s3).

> [!TIP]
> ეს მეტრიკები სასარგებლოა საცავის ოპერაციების შესრულების გასაგებად და პოტენციური „ბოთლეკების“ გამოსავლენად.


### `tuist_storage_get_object_size_size_bytes` (ჰისტოგრამა) {#tuist_storage_get_object_size_size_bytes-histogram}

ობიექტის ზომა (ბიტებში), მიღებული შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-size-size-bytes-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_size_duration_miliseconds` (ჰისტოგრამა) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

ობიექტის ზომის მიღების ხანგრძლივობა (მილიწამებში) შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-size-duration-miliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_size_count` (მრიცხველი) {#tuist_storage_get_object_size_count-counter}

ჯამური რაოდენობა, რამდენჯერაც მოხდა ობიექტის ზომის მიღება შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-size-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

ყველა ობიექტის წაშლის ხანგრძლივობა (მილიწამებში) შორეული საცავიდან.

#### ტეგები {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის slug, რომლის ობიექტებიც იშლება. |


### `tuist_storage_delete_all_objects_count` (მრიცხველი) {#tuist_storage_delete_all_objects_count-counter}

ჯამური რაოდენობა, რამდენჯერაც წაიშალა პროექტის ყველა ობიექტი შორეული საცავიდან.

#### ტეგები {#tuist-storage-delete-all-objects-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის slug, რომლის ობიექტებიც იშლება. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

ატვირთვის დაწყების ხანგრძლივობა (მილიწამებში) შორეულ საცავში.

#### ტეგები {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_start_upload_duration_count` (მრიცხველი) {#tuist_storage_multipart_start_upload_duration_count-counter}

ჯამური რაოდენობა, რამდენჯერაც დაიწყო ატვირთვა შორეულ საცავში.

#### ტეგები {#tuist-storage-multipart-start-upload-duration-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

ობიექტის სტრიქონად მიღების ხანგრძლივობა (მილიწამებში) შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_get_object_as_string_count` (რაოდენობა) {#tuist_storage_get_object_as_string_count-count}

ჯამური რაოდენობა, რამდენჯერაც მოხდა ობიექტის სტრიქონად მიღება შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-as-string-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_check_object_existence_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

შორეულ საცავში ობიექტის არსებობის შემოწმების ხანგრძლივობა (მილიწამებში).

#### ტეგები {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_check_object_existence_count` (რაოდენობა) {#tuist_storage_check_object_existence_count-count}

ჯამური რაოდენობა, რამდენჯერაც შემოწმდა ობიექტის არსებობა შორეულ საცავში.

#### ტეგები {#tuist-storage-check-object-existence-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

შორეულ საცავში ობიექტისთვის ჩამოსატვირთი წინასწარ ხელმოწერილი URL-ის გენერირების ხანგრძლივობა (მილიწამებში).

#### ტეგები {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_generate_download_presigned_url_count` (რაოდენობა) {#tuist_storage_generate_download_presigned_url_count-count}

ჯამური რაოდენობა, რამდენჯერაც გენერირდა ჩამოსატვირთი წინასწარ ხელმოწერილი URL შორეულ საცავში ობიექტისთვის.

#### ტეგები {#tuist-storage-generate-download-presigned-url-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

შორეულ საცავში ობიექტის ნაწილის ატვირთვის წინასწარ ხელმოწერილი URL-ის გენერირების ხანგრძლივობა (მილიწამებში).

#### ტეგები {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (რაოდენობა) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

ჯამური რაოდენობა, რამდენჯერაც გენერირდა ნაწილის ატვირთვის წინასწარ ხელმოწერილი URL შორეულ საცავში ობიექტისთვის.

#### ტეგები {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

შორეულ საცავში ატვირთვის დასრულების ხანგრძლივობა (მილიწამებში).

#### ტეგები {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |


### `tuist_storage_multipart_complete_upload_count` (რაოდენობა) {#tuist_storage_multipart_complete_upload_count-count}

ჯამური რაოდენობა, რამდენჯერაც დასრულდა ატვირთვა შორეულ საცავში.

#### ტეგები {#tuist-storage-multipart-complete-upload-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

---

## ავთენტიკაციის მეტრიკები {#authentication-metrics}

ავთენტიკაციასთან დაკავშირებული მეტრიკების ნაკრები.

### `tuist_authentication_token_refresh_error_total` (მთვლელი) {#tuist_authentication_token_refresh_error_total-counter}

ტოკენის განახლების შეცდომების ჯამური რაოდენობა.

#### ტეგები {#tuist-authentication-token-refresh-error-total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `cli_version` | Tuist CLI-ის ვერსია, რომელმაც შეცდომა გამოიწვია. |
| `reason` | ტოკენის განახლების შეცდომის მიზეზი, მაგალითად `invalid_token_type` ან `invalid_token`. |

---

## პროექტების მეტრიკები {#projects-metrics}

პროექტებთან დაკავშირებული მეტრიკების ნაკრები.

### `tuist_projects_total` (ბოლო მნიშვნელობა) {#tuist_projects_total-last_value}

პროექტების ჯამური რაოდენობა.

---

## ანგარიშების მეტრიკები {#accounts-metrics}

ანგარიშებთან (მომხმარებლები და ორგანიზაციები) დაკავშირებული მეტრიკების ნაკრები.

### `tuist_accounts_organizations_total` (ბოლო მნიშვნელობა) {#tuist_accounts_organizations_total-last_value}

ორგანიზაციების ჯამური რაოდენობა.

### `tuist_accounts_users_total` (ბოლო მნიშვნელობა) {#tuist_accounts_users_total-last_value}

მომხმარებლების ჯამური რაოდენობა.


## მონაცემთა ბაზის მეტრიკები {#database-metrics}

მონაცემთა ბაზასთან კავშირთან დაკავშირებული მეტრიკების ნაკრები.

რეპოზიტორიის პულის მეტრიკები შიგნით იკვლევა ყოველ 100 მწ-ში და შემდეგ ხდება Prometheus-ზე ხელმისაწვდომი `/metrics`-ზე. ქვემოთ მოცემული `last_value` მეტრიკები აჩვენებს პულის უახლეს მდგომარეობას სკრაპინგის დროს. წნევის მეტრიკები, რომლებიც ქვემოთაა, არის ამ 100 მწ ნიმუშებიდან მიღებული ჯამები, რაც მოკლე გაჯერების ფანჯრების აღმოჩენას აადვილებს მაშინაც კი, თუ ისინი შემდეგ სკრაპინგამდე აღდგებიან.

### `tuist_repo_pool_checkout_queue_length` (ბოლო მნიშვნელობა) {#tuist_repo_pool_checkout_queue_length-last_value}

მონაცემთა ბაზის იმ მოთხოვნების რაოდენობა, რომლებიც ელოდებიან მონაცემთა ბაზის კავშირზე განაწილებას.

#### ტეგები {#tuist_repo_pool_checkout_queue_length-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (ბოლო მნიშვნელობა) {#tuist_repo_pool_ready_conn_count-last_value}

მონაცემთა ბაზის იმ კავშირების რაოდენობა, რომლებიც მზად არიან მონაცემთა ბაზის მოთხოვნაზე განაწილებისთვის.

#### ტეგები {#tuist_repo_pool_ready_conn_count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_size` (ბოლო მნიშვნელობა) {#tuist_repo_pool_size-last_value}

პულში კონფიგურირებული კავშირების რაოდენობა.

#### ტეგები {#tuist_repo_pool_size-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების ჯამური რაოდენობა (იზრდება 1-ით ყოველ გამოკითხვაზე). გამოიყენეთ ეს როგორც მნიშვნელი დატვირთულობის ან შიმშილის პროცენტების გამოთვლისას: `rate(busy_samples) / rate(total_samples)` ან `rate(starved_samples) / rate(total_samples)`.

#### ტეგები {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

რიგში მყოფი checkout მოთხოვნების ჯამი, დაკვირვებული რეპოზიტორიის პულის გამოკითხვების განმავლობაში. ეს სასარგებლოა პულის კონკურენციის მოკლე აფეთქებების აღმოჩენისთვის, რომლებიც შესაძლოა არ ჩანდეს მხოლოდ რიგის სიგრძის უახლეს ნიმუშში.

#### ტეგები {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების რაოდენობა, სადაც მინიმუმ ერთი მონაცემთა ბაზის checkout მოთხოვნა ელოდებოდა რიგში.

#### ტეგები {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების რაოდენობა, სადაც checkout მოთხოვნები იყო რიგში და არ იყო ხელმისაწვდომი მზა კავშირები. აქ მდგრადი ზრდა ჩვეულებრივ ნიშნავს, რომ პული გაჯერებულია.

#### ტეგები {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read`, ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (მრიცხველი) {#tuist_repo_pool_db_connection_connected-counter}

მონაცემთა ბაზასთან დამყარებული კავშირების რაოდენობა.

### `tuist_repo_pool_db_connection_disconnected` (მრიცხველი) {#tuist_repo_pool_db_connection_disconnected-counter}

მონაცემთა ბაზიდან გაწყვეტილი კავშირების რაოდენობა.

#### ტეგები {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `tag` | DBConnection-ის მოსმენის ტეგი, რომელიც განსაზღვრავს გამომუშავებელ რეპოზიტორიას. |

## HTTP მეტრიკები {#http-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება Tuist-ის ურთიერთქმედებას სხვა სერვისებთან HTTP-ის საშუალებით.

### `tuist_http_request_count` (მრიცხველი) {#tuist_http_request_count-last_value}

გამავალი HTTP მოთხოვნების რაოდენობა.

### `tuist_http_request_duration_nanoseconds_sum` (ჯამი) {#tuist_http_request_duration_nanoseconds_sum-last_value}

გამავალი მოთხოვნების ხანგრძლივობის ჯამი (მათ შორის დრო, რომელიც მათ დაჰარჯეს კავშირზე მიბმის მოლოდინში).

### `tuist_http_request_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
გამავალი მოთხოვნების ხანგრძლივობის განაწილება (მათ შორის დრო, რომელიც მათ დაჰარჯეს კავშირზე მიბმის მოლოდინში).

### `tuist_http_queue_count` (მრიცხველი) {#tuist_http_queue_count-counter}

პულიდან ამოღებული მოთხოვნების რაოდენობა.

### `tuist_http_queue_duration_nanoseconds_sum` (ჯამი) {#tuist_http_queue_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება პულიდან კავშირის ამოღებას.

### `tuist_http_queue_idle_time_nanoseconds_sum` (ჯამი) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდებოდა ამოღებას.

### `tuist_http_queue_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

დრო, რომელიც სჭირდება პულიდან კავშირის ამოღებას.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდებოდა ამოღებას.

### `tuist_http_connection_count` (მრიცხველი) {#tuist_http_connection_count-counter}

დამყარებული კავშირების რაოდენობა.

### `tuist_http_connection_duration_nanoseconds_sum` (ჯამი) {#tuist_http_connection_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება ჰოსტთან კავშირის დამყარებას.

### `tuist_http_connection_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ჰოსტთან კავშირის დამყარებისთვის საჭირო დროის განაწილება.

### `tuist_http_send_count` (მრიცხველი) {#tuist_http_send_count-counter}

მოთხოვნების რაოდენობა, რომლებიც გაიგზავნა პულიდან კავშირზე მიბმის შემდეგ.

### `tuist_http_send_duration_nanoseconds_sum` (ჯამი) {#tuist_http_send_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება მოთხოვნების დასრულებას პულიდან კავშირზე მიბმის შემდეგ.

### `tuist_http_send_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

მოთხოვნების დასრულებისთვის საჭირო დროის განაწილება პულიდან კავშირზე მიბმის შემდეგ.

### `tuist_http_receive_count` (მრიცხველი) {#tuist_http_receive_count-counter}

მიღებული პასუხების რაოდენობა გაგზავნილი მოთხოვნებიდან.

### `tuist_http_receive_duration_nanoseconds_sum` (ჯამი) {#tuist_http_receive_duration_nanoseconds_sum-sum}

პასუხების მიღებაზე დახარჯული დრო.

### `tuist_http_receive_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

პასუხების მიღებაზე დახარჯული დროის განაწილება.

### `tuist_http_queue_available_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_available_connections-last_value}

რიგში ხელმისაწვდომი კავშირების რაოდენობა.

### `tuist_http_queue_in_use_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_in_use_connections-last_value}

რიგში გამოყენებაში მყოფი კავშირების რაოდენობა.
