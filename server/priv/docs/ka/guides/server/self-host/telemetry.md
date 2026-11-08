---
{
  "title": "ტელემეტრია",
  "titleTemplate": ":title | საკუთარ სერვერზე განთავსება | სერვერი | სახელმძღვანელოები | Tuist",
  "description": "აწარმოეთ თქვენი Tuist სერვერის მონიტორინგი Prometheus მეტრიკებით, OpenTelemetry ტრეისებით და ლოგების გადამისამართებით."
}
---
# ტელემეტრია {#telemetry}

Tuist სამ ურთიერთშემავსებელ დაკვირვებადობის სიგნალს გთავაზობთ: **მეტრიკები** (Prometheus), **ტრეისები** (OpenTelemetry) და **ლოგები** (Loki-თან თავსებადი). სამივე არჩევითია და დამოუკიდებლად შეიძლება ჩართვა.

## განაწილებული ტრეისინგი (OpenTelemetry) {#opentelemetry}

Tuist მხარს უჭერს [OpenTelemetry](https://opentelemetry.io/)-ს განაწილებული ტრეისინგისთვის. ჩართვისას სერვერი გამოსცემს ტრეისებს HTTP მოთხოვნებისთვის (Phoenix და Bandit), მონაცემთა ბაზის კითხვებისთვის (Ecto), გამავალი HTTP გამოძახებებისთვის (Finch) და Broadway შეტყობინებების დამუშავებისთვის. ეს ტრეისები საშუალებას გაძლევთ გაიგოთ მოთხოვნის ლატენტურობა, იდენტიფიცირება მოახდინოთ ნელი კითხვებისა და მოთხოვნებს მიჰყვეთ სერვისებს შორის.

### კონფიგურაცია {#opentelemetry-configuration}

ტრეისების ექსპორტის ჩასართავად დააყენეთ შემდეგი გარემოს ცვლადი:

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector-ის gRPC წერტილი (მაგ., Grafana Alloy, Jaeger ან ნებისმიერი OTLP-თან თავსებადი კოლექტორი) | არა | | `http://localhost:4317` |

როცა ეს ცვლადი არ არის დაყენებული, ტრეისინგი გამორთულია და დამატებით დატვირთვას არ ქმნის.

### ინსტრუმენტირებული ბიბლიოთეკები {#opentelemetry-instrumented-libraries}

ტრეისინგის ჩართვისას შემდეგი ბიბლიოთეკები ავტომატურად ინსტრუმენტირდება:

- **Bandit** — HTTP სერვერის კავშირის სპენები
- **Phoenix** — მოთხოვნის სიცოცხლის ციკლის სპენები (კონტროლერის ქმედებები, LiveView)
- **Ecto** — მონაცემთა ბაზის კითხვის სპენები კითხვის მეტამონაცემებით
- **Finch** — გამავალი HTTP კლიენტის მოთხოვნის სპენები
- **Broadway** — შეტყობინებების დამუშავების პაიპლაინის სპენები

### მაგალითი Grafana Alloy-ით {#opentelemetry-alloy-example}

თუ კოლექტორად [Grafana Alloy](https://grafana.com/docs/alloy/latest/)-ს იყენებთ, კონფიგურაციით მიიღეთ OTLP ტრეისები და გადაამისამართეთ ისინი თქვენს ტრეისინგის ბექენდზე (მაგ., Grafana Cloud Tempo):

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

შემდეგ დააყენეთ `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT`, რათა მიუთითოთ Alloy-ის ინსტანციაზე, მაგ., `http://alloy:4317`.

## ლოგების გადამისამართება (Loki) {#log-forwarding}

Tuist-ს შეუძლია აპლიკაციის ლოგები [Loki](https://grafana.com/oss/loki/)-თან თავსებად წერტილზე გადაამისამართოს. ეს საშუალებას გაძლევთ ლოგები მეტრიკებთან და ტრეისებთან ერთად გააერთიანოთ სრული დაკვირვებადობისთვის. ლოგები იგზავნება Loki HTTP push API-ით (`/loki/api/v1/push`) და შეიცავს ლეიბლებს `app`, `env` და `level`.

### კონფიგურაცია {#log-forwarding-configuration}

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki-თან თავსებადი push API წერტილის საბაზისო URL | არა | | `http://localhost:3100` |

როცა ეს ცვლადი არ არის დაყენებული, ლოგების გადამისამართება გამორთულია.

### მაგალითი Grafana Alloy-ით {#log-forwarding-alloy-example}

Grafana Alloy-ს შეუძლია იმოქმედოს როგორც ლოკალური ლოგების რელეიმ მისი [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) კომპონენტის გამოყენებით:

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

`TUIST_LOKI_URL`-ის პირდაპირ Loki-ის ინსტანციაზე მიმართვაც შეგიძლიათ, თუ ის push API-ს ხელმისაწვდომს ხდის.

## Prometheus მეტრიკები {#prometheus-metrics}

Tuist სერვერის მიერ შეგროვებული მეტრიკების შესანახად შეგიძლიათ გამოიყენოთ [Prometheus](https://prometheus.io/) და ვიზუალიზაციის ინსტრუმენტი, მაგალითად [Grafana](https://grafana.com/), რათა შექმნათ თქვენს საჭიროებებზე მორგებული მორგებული დაშბორდი. Prometheus-ის მეტრიკები ხელმისაწვდომია `/metrics` წერტილში პორტზე 9091. Prometheus-ის [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) უნდა იყოს დაყენებული 10_000 წამზე ნაკლებად (ჩვენ გირჩევთ 30 წამს, რათა დაკვირვებადობა და მეტრიკების შეგროვების ხარჯები დააბალანსოთ).

## რეალური მომხმარებლის მონიტორინგი {#real-user-monitoring}

Tuist-ს შეუძლია ანგარიში გაუწიოს ბრაუზერის მუშაობას მარკეტინგის საიტიდან, დოკუმენტაციიდან და დაშბორდიდან [Grafana Faro](https://grafana.com/oss/faro/) Web SDK-ის გამოყენებით, რომელიც ჩართულია მიწოდებულ JavaScript-ში. ის აღრიცხავს Core Web Vitals-ს (მათ შორის Largest Contentful Paint-ს), დაუჭერელ შეცდომებს და გვერდის ნახვებს, და აგზავნის მათ თქვენს მიერ გაშვებულ [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/)-ზე — მაგალითად, `faro.receiver` კომპონენტზე Grafana Alloy-ში, რომელიც გადაამისამართებს Loki-სა და Tempo-ზე.

### კონფიგურაცია {#real-user-monitoring-configuration}

| გარემოს ცვლადი | აღწერა | სავალდებულო | ნაგულისხმები | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | URL, სადაც ბრაუზერი აგზავნის Faro პეილოადებს | არა | | `/-/faro` |

> [!NOTE]
> რეალური მომხმარებლის მონიტორინგი ჩართულია მხოლოდ მაშინ, როცა `TUIST_FARO_COLLECTOR_URL` დაყენებულია. მის გარეშე ბრაუზერის ტელემეტრია არ გროვდება და მესამე მხარის სკრიპტები არ იტვირთება.

იგივე წყაროს მქონე გზა, როგორიცაა `/-/faro`, თავს არიდებს ჯვარედინ წყაროს მოთხოვნებს და ტოვებს ბრაუზერის შინაარსის უსაფრთხოების პოლიტიკას უცვლელად. მიმართეთ ის თქვენს Faro მიმღებთან თქვენი ingress-ის მეშვეობით.

### რა გროვდება {#real-user-monitoring-collected}

- **Web vitals**: LCP, CLS, INP, FCP და TTFB, რომლებსაც ბრაუზერი ავტომატურად აღრიცხავს
- **გვერდის ნახვები**: ფიქსირდება ჩატვირთვისას და Phoenix LiveView ნავიგაციისას
- **ნახვები**: ყოველი პეილოადი შეიცავს სექციას, რომელმაც ის წარმოქმნა — `marketing`, `docs`, `dashboard` ან `api-docs`
- **შეცდომები**: დაუჭერელი გამონაკლისები და დაუმუშავებელი promise-ების უარყოფები

### კონფიდენციალურობის მოსაზრებები {#real-user-monitoring-privacy}

- მომხმარებლის იდენტიფიკაცია არ არის მიბმული: პეილოადები არ შეიცავს მომხმარებლის ID-ს, ელფოსტას ან ანგარიშს
- სესიები არ ინახება ვიზიტებს შორის, ამიტომ ბრაუზერის საცავში არაფერი იწერება
- კონსოლის ჩაჭრა გამორთულია, ამიტომ აპლიკაციის ლოგების გამოტანა არასდროს იგზავნება ბრაუზერიდან

## Elixir მეტრიკები {#elixir-metrics}

ნაგულისხმევად ჩვენ ვრთავთ Elixir რანთაიმის, BEAM-ის, Elixir-ის და ზოგიერთი ჩვენს მიერ გამოყენებული ბიბლიოთეკის მეტრიკებს. ქვემოთ მოცემულია ზოგიერთი მეტრიკა, რომლის ნახვაც შეგიძლიათ:

- [აპლიკაცია](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

გირჩევთ, გადახედოთ ამ გვერდებს, რათა გაიგოთ, რომელი მეტრიკებია ხელმისაწვდომი და როგორ გამოიყენოთ ისინი.

## გაშვებების მეტრიკები {#runs-metrics}

მეტრიკების ნაკრები, რომელიც დაკავშირებულია Tuist Runs-თან.

### `tuist_runs_total` (მთვლელი) {#tuist_runs_total-counter}

Tuist Runs-ის საერთო რაოდენობა.

#### ტეგები {#tuist-runs-total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც გაეშვა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულიანი მნიშვნელობა, რომელიც მიუთითებს, იყო შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `0` `success`-ის შემთხვევაში, `1` `failure`-ის შემთხვევაში. |

### `tuist_runs_duration_milliseconds` (ჰისტოგრამა) {#tuist_runs_duration_milliseconds-histogram}

თითოეული tuist გაშვების საერთო ხანგრძლივობა მილიწამებში.

#### ტეგები {#tuist-runs-duration-miliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც გაეშვა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულიანი მნიშვნელობა, რომელიც მიუთითებს, იყო შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `0` `success`-ის შემთხვევაში, `1` `failure`-ის შემთხვევაში. |

## ქეშის მეტრიკები {#cache-metrics}

მეტრიკების ნაკრები, რომელიც დაკავშირებულია Tuist Cache-თან.

### `tuist_cache_events_total` (მთვლელი) {#tuist_cache_events_total-counter}

ბინარული ქეშის მოვლენების საერთო რაოდენობა.

#### ტეგები {#tuist-cache-events-total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `event_type` | შეიძლება იყოს `local_hit`, `remote_hit` ან `miss`. |

### `tuist_cache_uploads_total` (მთვლელი) {#tuist_cache_uploads_total-counter}

ბინარულ ქეშში ატვირთვების რაოდენობა.

### `tuist_cache_uploaded_bytes` (ჯამი) {#tuist_cache_uploaded_bytes-sum}

ბინარულ ქეშში ატვირთული ბაიტების რაოდენობა.

### `tuist_cache_downloads_total` (მთვლელი) {#tuist_cache_downloads_total-counter}

ბინარული ქეშიდან ჩამოტვირთვების რაოდენობა.

### `tuist_cache_downloaded_bytes` (ჯამი) {#tuist_cache_downloaded_bytes-sum}

ბინარული ქეშიდან ჩამოტვირთული ბაიტების რაოდენობა.

---

## პრევიუების მეტრიკები {#previews-metrics}

მეტრიკების ნაკრები, რომელიც დაკავშირებულია პრევიუების ფუნქციასთან.

### `tuist_previews_uploads_total` (ჯამი) {#tuist_previews_uploads_total-counter}

ატვირთული პრევიუების საერთო რაოდენობა.

### `tuist_previews_downloads_total` (ჯამი) {#tuist_previews_downloads_total-counter}

ჩამოტვირთული პრევიუების საერთო რაოდენობა.

---

## საცავის მეტრიკები {#storage-metrics}

მეტრიკების ნაკრები, რომელიც დაკავშირებულია არტიფაქტების შენახვასთან შორეულ საცავში (მაგ., s3).

> [!TIP]
> ეს მეტრიკები სასარგებლოა საცავის ოპერაციების წარმადობის გასაგებად და პოტენციური „ბოთლის ყელის“ იდენტიფიცირებისთვის.


### `tuist_storage_get_object_size_size_bytes` (ჰისტოგრამა) {#tuist_storage_get_object_size_size_bytes-histogram}

შორეული საცავიდან მიღებული ობიექტის ზომა (ბაიტებში).

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


### `tuist_storage_get_object_size_count` (მთვლელი) {#tuist_storage_get_object_size_count-counter}

რაოდენობა, რამდენჯერაც მოხდა ობიექტის ზომის მიღება შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-size-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

ყველა ობიექტის წაშლის ხანგრძლივობა (მილიწამებში) შორეული საცავიდან.

#### ტეგები {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის სლაგი, რომლის ობიექტებიც იშლება. |


### `tuist_storage_delete_all_objects_count` (მთვლელი) {#tuist_storage_delete_all_objects_count-counter}

რაოდენობა, რამდენჯერაც ყველა პროექტის ობიექტი წაიშალა შორეული საცავიდან.

#### ტეგები {#tuist-storage-delete-all-objects-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის სლაგი, რომლის ობიექტებიც იშლება. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

ატვირთვის დაწყების ხანგრძლივობა (მილიწამებში) შორეულ საცავში.

#### ტეგები {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_start_upload_duration_count` (მთვლელი) {#tuist_storage_multipart_start_upload_duration_count-counter}

რაოდენობა, რამდენჯერაც დაიწყო ატვირთვა შორეულ საცავში.

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

### `tuist_storage_get_object_as_string_count` (მთვლელი) {#tuist_storage_get_object_as_string_count-count}

რაოდენობა, რამდენჯერაც მოხდა ობიექტის სტრიქონად მიღება შორეული საცავიდან.

#### ტეგები {#tuist-storage-get-object-as-string-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_check_object_existence_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

ობიექტის არსებობის შემოწმების ხანგრძლივობა (მილიწამებში) შორეულ საცავში.

#### ტეგები {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_check_object_existence_count` (მთვლელი) {#tuist_storage_check_object_existence_count-count}

რაოდენობა, რამდენჯერაც შემოწმდა ობიექტის არსებობა შორეულ საცავში.

#### ტეგები {#tuist-storage-check-object-existence-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

ჩამოტვირთვის წინასწარ ხელმოწერილი URL-ის გენერაციის ხანგრძლივობა (მილიწამებში) შორეული საცავის ობიექტისთვის.

#### ტეგები {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |


### `tuist_storage_generate_download_presigned_url_count` (მთვლელი) {#tuist_storage_generate_download_presigned_url_count-count}

რაოდენობა, რამდენჯერაც გენერირდა ჩამოტვირთვის წინასწარ ხელმოწერილი URL შორეული საცავის ობიექტისთვის.

#### ტეგები {#tuist-storage-generate-download-presigned-url-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

ნაწილობრივი ატვირთვის წინასწარ ხელმოწერილი URL-ის გენერაციის ხანგრძლივობა (მილიწამებში) შორეული საცავის ობიექტისთვის.

#### ტეგები {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ატვირთვის ID. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (მთვლელი) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

რაოდენობა, რამდენჯერაც გენერირდა ნაწილობრივი ატვირთვის წინასწარ ხელმოწერილი URL შორეული საცავის ობიექტისთვის.

#### ტეგები {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ატვირთვის ID. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

შორეულ საცავში ატვირთვის დასრულების ხანგრძლივობა (მილიწამებში).

#### ტეგები {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ატვირთვის ID. |


### `tuist_storage_multipart_complete_upload_count` (მთვლელი) {#tuist_storage_multipart_complete_upload_count-count}

რაოდენობა, რამდენჯერაც დასრულდა ატვირთვა შორეულ საცავში.

#### ტეგები {#tuist-storage-multipart-complete-upload-count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის ძიების გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ატვირთვის ID. |

---

## ავტორიზაციის მეტრიკები {#authentication-metrics}

ავტორიზაციასთან დაკავშირებული მეტრიკების ნაკრები.

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

რეპო-პულის მეტრიკები შიგნით იღებენ სინჯებს ყოველ 100 მწ-ში, შემდეგ კი ხდება Prometheus-ზე გამოქვეყნება `/metrics`-ზე. ქვემოთ მოცემული `last_value` მეტრიკები აჩვენებს პულის უახლეს მდგომარეობას შეგროვების დროს. წნევის მეტრიკები, რომლებიც ქვემოთაა, არის ამ 100 მწ-იანი სინჯებიდან მიღებული ჯამები, რაც მოკლე გაჯერების ფანჯრების აღმოჩენას აადვილებს, მაშინაც კი, თუ ისინი შემდეგ შეგროვებამდე აღდგებიან.

### `tuist_repo_pool_checkout_queue_length` (ბოლო მნიშვნელობა) {#tuist_repo_pool_checkout_queue_length-last_value}

მონაცემთა ბაზის იმ მოთხოვნების რაოდენობა, რომლებიც რიგში ელოდებიან მონაცემთა ბაზის კავშირზე მიბმას.

#### ტეგები {#tuist_repo_pool_checkout_queue_length-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (ბოლო მნიშვნელობა) {#tuist_repo_pool_ready_conn_count-last_value}

მონაცემთა ბაზის იმ კავშირების რაოდენობა, რომლებიც მზად არიან მონაცემთა ბაზის მოთხოვნაზე მიბმისთვის.

#### ტეგები {#tuist_repo_pool_ready_conn_count-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_size` (ბოლო მნიშვნელობა) {#tuist_repo_pool_size-last_value}

პულში კონფიგურირებული კავშირების რაოდენობა.

#### ტეგები {#tuist_repo_pool_size-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

რეპო-პულის გამოკითხვების ჯამური რაოდენობა (იზრდება 1-ით ყოველ გამოკითხვაზე). გამოიყენეთ ეს როგორც მნიშვნელი დატვირთვის ან შიმშილის პროცენტების გამოთვლისას: `rate(busy_samples) / rate(total_samples)` ან `rate(starved_samples) / rate(total_samples)`.

#### ტეგები {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

რიგში მყოფი checkout მოთხოვნების ჯამი, რომელიც დაფიქსირდა რეპო-პულის გამოკითხვების დროს. ეს სასარგებლოა პულის მოკლე კონკურენციის პიკების აღმოსაჩენად, რომლებიც შესაძლოა არ ჩანდეს მხოლოდ რიგის სიგრძის უახლეს სინჯში.

#### ტეგები {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

რეპო-პულის გამოკითხვების რაოდენობა, როდესაც მინიმუმ ერთი მონაცემთა ბაზის checkout მოთხოვნა ელოდა რიგში.

#### ტეგები {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

რეპო-პულის გამოკითხვების რაოდენობა, როდესაც checkout მოთხოვნები იყო რიგში და არ იყო ხელმისაწვდომი მზა კავშირები. ამ მაჩვენებლის მდგრადი ზრდა ჩვეულებრივ ნიშნავს, რომ პული გადატვირთულია.

#### ტეგები {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოსცა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (მთვლელი) {#tuist_repo_pool_db_connection_connected-counter}

მონაცემთა ბაზასთან დამყარებული კავშირების რაოდენობა.

### `tuist_repo_pool_db_connection_disconnected` (მთვლელი) {#tuist_repo_pool_db_connection_disconnected-counter}

მონაცემთა ბაზიდან გაწყვეტილი კავშირების რაოდენობა.

#### ტეგები {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| ტეგი | აღწერა |
|--- | ---- |
| `tag` | DBConnection-ის მსმენელის ტეგი, რომელიც განსაზღვრავს გამომცემ რეპოზიტორიას. |

## HTTP მეტრიკები {#http-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება Tuist-ის ურთიერთქმედებას სხვა სერვისებთან HTTP-ის საშუალებით.

### `tuist_http_request_count` (მთვლელი) {#tuist_http_request_count-last_value}

გამავალი HTTP მოთხოვნების რაოდენობა.

### `tuist_http_request_duration_nanoseconds_sum` (ჯამი) {#tuist_http_request_duration_nanoseconds_sum-last_value}

გამავალი მოთხოვნების ხანგრძლივობის ჯამი (მათ შორის დრო, რომელიც მათ დაჰარჯეთ კავშირზე მინიჭების მოლოდინში).

### `tuist_http_request_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
გამავალი მოთხოვნების ხანგრძლივობის განაწილება (მათ შორის დრო, რომელიც მათ დაჰარჯეთ კავშირზე მინიჭების მოლოდინში).

### `tuist_http_queue_count` (მთვლელი) {#tuist_http_queue_count-counter}

პულიდან მიღებული მოთხოვნების რაოდენობა.

### `tuist_http_queue_duration_nanoseconds_sum` (ჯამი) {#tuist_http_queue_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება კავშირის მიღებას პულიდან.

### `tuist_http_queue_idle_time_nanoseconds_sum` (ჯამი) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდა მიღებას.

### `tuist_http_queue_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

დრო, რომელიც სჭირდება კავშირის მიღებას პულიდან.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდა მიღებას.

### `tuist_http_connection_count` (მთვლელი) {#tuist_http_connection_count-counter}

დამყარებული კავშირების რაოდენობა.

### `tuist_http_connection_duration_nanoseconds_sum` (ჯამი) {#tuist_http_connection_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება ჰოსტთან კავშირის დამყარებას.

### `tuist_http_connection_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ჰოსტთან კავშირის დამყარებისთვის საჭირო დროის განაწილება.

### `tuist_http_send_count` (მთვლელი) {#tuist_http_send_count-counter}

მოთხოვნების რაოდენობა, რომლებიც გაიგზავნა პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_send_duration_nanoseconds_sum` (ჯამი) {#tuist_http_send_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება მოთხოვნების დასრულებას პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_send_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

მოთხოვნების დასრულებისთვის საჭირო დროის განაწილება პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_receive_count` (მთვლელი) {#tuist_http_receive_count-counter}

გაგზავნილი მოთხოვნებიდან მიღებული პასუხების რაოდენობა.

### `tuist_http_receive_duration_nanoseconds_sum` (ჯამი) {#tuist_http_receive_duration_nanoseconds_sum-sum}

პასუხების მიღებაზე დახარჯული დრო.

### `tuist_http_receive_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

პასუხების მიღებაზე დახარჯული დროის განაწილება.

### `tuist_http_queue_available_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_available_connections-last_value}

რიგში ხელმისაწვდომი კავშირების რაოდენობა.

### `tuist_http_queue_in_use_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_in_use_connections-last_value}

გამოყენებაში მყოფი რიგის კავშირების რაოდენობა.
