---
{
  "title": "ტელემეტრია",
  "titleTemplate": ":title | თვითმასპინძლობა | სერვერი | სახელმძღვანელოები | Tuist",
  "description": "თქვენი Tuist სერვერის მონიტორინგი Prometheus მეტრიკებით, OpenTelemetry ტრეისებით და ლოგების გადამისამართებით."
}
---
# ტელემეტრია {#telemetry}

Tuist გთავაზობთ დაკვირვების სამ დამატებით სიგნალს: **მეტრიკები** (Prometheus), **ტრეისინგი** (OpenTelemetry) და **ლოგები** (Loki-თან თავსებადი). სამივე არჩევითია და შეიძლება დამოუკიდებლად ჩართვა.

## განაწილებული ტრეისინგი (OpenTelemetry) {#opentelemetry}

Tuist მხარს უჭერს [OpenTelemetry](https://opentelemetry.io/)-ს განაწილებული ტრეისინგისთვის. ჩართვისას სერვერი გამოყოფს ტრეისებს HTTP მოთხოვნებისთვის (Phoenix და Bandit), მონაცემთა ბაზის კითხვებისთვის (Ecto), გამომავალი HTTP ზარებისთვის (Finch) და Broadway შეტყობინებების დამუშავებისთვის. ეს ტრეისები გაძლევთ საშუალებას გაიგოთ მოთხოვნების ლატენტობა, აღმოაჩინოთ ნელი კითხვები და მიჰყვეთ მოთხოვნებს სერვისებს შორის.

### კონფიგურაცია {#opentelemetry-configuration}

ტრეისების ექსპორტის ჩასართავად დააყენეთ შემდეგი გარემოს ცვლადი:

| გარემოს ცვლადი | აღწერა | აუცილებელია | ნაგულისხმევი | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector-ის gRPC წერტილი (მაგ., Grafana Alloy, Jaeger ან ნებისმიერი OTLP-თან თავსებადი კოლექტორი) | არა | | `http://localhost:4317` |

როცა ეს ცვლადი არ არის დაყენებული, ტრეისინგი გამორთულია და არ ქმნის დამატებით დატვირთვას.

### ინსტრუმენტირებული ბიბლიოთეკები {#opentelemetry-instrumented-libraries}

ტრეისინგის ჩართვისას შემდეგი ბიბლიოთეკები ავტომატურად ინსტრუმენტირდება:

- **Bandit** – HTTP სერვერის კავშირის სპანები
- **Phoenix** – მოთხოვნის სიცოცხლის ციკლის სპანები (კონტროლერის ქმედებები, LiveView)
- **Ecto** – მონაცემთა ბაზის კითხვის სპანები მეტამონაცემებით
- **Finch** – გამომავალი HTTP კლიენტის მოთხოვნის სპანები
- **Broadway** – შეტყობინებების დამუშავების პაიპლაინის სპანები

### მაგალითის კონფიგურაცია Grafana Alloy-ით {#opentelemetry-alloy-example}

თუ თქვენ იყენებთ [Grafana Alloy](https://grafana.com/docs/alloy/latest/)-ს როგორც კოლექტორს, დააკონფიგურირეთ ის OTLP ტრეისების მიღებისა და თქვენს ტრეისინგის ბექენდზე გადაგზავნისთვის (მაგ., Grafana Cloud Tempo):

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

Tuist-ს შეუძლია აპლიკაციის ლოგების გადამისამართება [Loki](https://grafana.com/oss/loki/)-თან თავსებად წერტილზე. ეს საშუალებას გაძლევთ ცენტრალიზებულად შეინახოთ ლოგები მეტრიკებთან და ტრეისებთან ერთად სრული დაკვირვებისთვის. ლოგები იგზავნება Loki HTTP push API-ით (`/loki/api/v1/push`) და შეიცავს ჭდეებს `app`, `env` და `level`-ისთვის.

### კონფიგურაცია {#log-forwarding-configuration}

| გარემოს ცვლადი | აღწერა | აუცილებელია | ნაგულისხმევი | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_LOKI_URL` | Loki-თან თავსებადი push API წერტილის საბაზო URL | არა | | `http://localhost:3100` |

როცა ეს ცვლადი არ არის დაყენებული, ლოგების გადამისამართება გამორთულია.

### მაგალითის კონფიგურაცია Grafana Alloy-ით {#log-forwarding-alloy-example}

Grafana Alloy-ს შეუძლია იმოქმედოს როგორც ლოკალურმა ლოგების რელემ მისი [`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/) კომპონენტის გამოყენებით:

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

ასევე შეგიძლიათ `TUIST_LOKI_URL` პირდაპირ მიუთითოთ Loki-ის ინსტანციაზე, თუ ის ხელმისაწვდომს ხდის push API-ს.

## Prometheus მეტრიკები {#prometheus-metrics}

შეგიძლიათ აგრიგოთ Tuist სერვერის მიერ შეგროვებული მეტრიკები [Prometheus](https://prometheus.io/)-ის და ვიზუალიზაციის ინსტრუმენტის, მაგალითად [Grafana](https://grafana.com/)-ის გამოყენებით, რათა შექმნათ თქვენს საჭიროებებზე მორგებული პერსონალური დაშბორდი. Prometheus-ის მეტრიკები ხელმისაწვდომია `/metrics` ენდპოინტზე 9091 პორტზე. Prometheus-ის [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) უნდა იყოს დაყენებული 10_000 წამზე ნაკლებად (ჩვენ გირჩევთ 30 წამს, რათა ბალანსი დავიცვათ დაკვირვებასა და მეტრიკების აგრეგაციის ხარჯებს შორის).

## რეალური მომხმარებლების მონიტორინგი {#real-user-monitoring}

Tuist-ს შეუძლია შეატყობინოს ბრაუზერის შესრულება მარკეტინგული საიტიდან, დოკუმენტაციიდან და დაშბორდიდან [Grafana Faro](https://grafana.com/oss/faro/) Web SDK-ის გამოყენებით, რომელიც ჩაშენებულია მიწოდებულ JavaScript-ში. ის იჭერს ძირითად ვებ-ვიტალებს (მათ შორის Largest Contentful Paint), დაუჭერელ შეცდომებს და გვერდის ნახვებს, და აგზავნის მათ თქვენს მიერ გაშვებულ [Faro receiver](https://grafana.com/docs/alloy/latest/reference/components/faro/faro.receiver/)-ზე — მაგალითად, `faro.receiver` კომპონენტზე Grafana Alloy-ში, რომელიც გადაამისამართებს Loki-სა და Tempo-ზე.

### კონფიგურაცია {#real-user-monitoring-configuration}

| გარემოს ცვლადი | აღწერა | აუცილებელია | ნაგულისხმევი | მაგალითი |
| --- | --- | --- | --- | --- |
| `TUIST_FARO_COLLECTOR_URL` | URL, რომელზეც ბრაუზერი აგზავნის Faro პეილოადებს | არა | | `/-/faro` |

> [!NOTE]
> რეალური მომხმარებლების მონიტორინგი ჩართულია მხოლოდ მაშინ, როცა `TUIST_FARO_COLLECTOR_URL` არის დაყენებული. მის გარეშე, ბრაუზერის ტელემეტრია არ გროვდება და მესამე მხარის სკრიპტი არ იტვირთება.

იგივე წყაროს გზა, როგორიცაა `/-/faro`, თავს არიდებს ჯვარედინ წყაროს მოთხოვნებს და ინარჩუნებს ბრაუზერის შინაარსის უსაფრთხოების პოლიტიკას უცვლელად. მიუთითეთ ის თქვენს Faro მიმღებზე თქვენი ingress-ის მეშვეობით.

### რა გროვდება {#real-user-monitoring-collected}

- **ვებ-ვიტალები**: LCP, CLS, INP, FCP და TTFB, რომლებსაც ბრაუზერი ავტომატურად იჭერს
- **გვერდის ნახვები**: ფიქსირდება ჩატვირთვისას და Phoenix LiveView ნავიგაციისას
- **ნახვები**: თითოეული პეილოადი შეიცავს სექციას, რომელმაც ის წარმოქმნა — `marketing`, `docs`, `dashboard` ან `api-docs`
- **შეცდომები**: დაუჭერელი გამონაკლისები და დაუმუშავებელი promise უარყოფები

### კონფიდენციალურობის საკითხები {#real-user-monitoring-privacy}

- მომხმარებლის იდენტიფიკაცია არ არის მიბმული: პეილოადები არ შეიცავს მომხმარებლის ID-ს, ელფოსტას ან ანგარიშს
- სესიები არ ინახება ვიზიტებს შორის, ამიტომ არაფერი იწერება ბრაუზერის საცავში
- კონსოლის ჩაწერა გამორთულია, ამიტომ აპლიკაციის ლოგების გამოტანა არასდროს იგზავნება ბრაუზერიდან

## Elixir მეტრიკები {#elixir-metrics}

ნაგულისხმევად ჩვენ ვრთავთ Elixir runtime-ის, BEAM-ის, Elixir-ის და ზოგიერთი ჩვენს მიერ გამოყენებული ბიბლიოთეკის მეტრიკებს. ქვემოთ მოცემულია ზოგიერთი მეტრიკა, რომლის ნახვაც შეგიძლიათ:

- [აპლიკაცია](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

ჩვენ გირჩევთ გადახედოთ ამ გვერდებს, რათა გაიგოთ, რომელი მეტრიკებია ხელმისაწვდომი და როგორ გამოიყენოთ ისინი.

## გაშვებების მეტრიკები {#runs-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება Tuist Runs-ს.

### `tuist_runs_total` (მრიცხველი) {#tuist_runs_total-counter}

Tuist გაშვებების საერთო რაოდენობა.

#### ჭდეები {#tuist-runs-total-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც შესრულდა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულის მნიშვნელობა, რომელიც მიუთითებს, იყო თუ არა შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `1` `success`-ის შემთხვევაში, `failure` `0`-ის შემთხვევაში. |

### `tuist_runs_duration_milliseconds` (ჰისტოგრამა) {#tuist_runs_duration_milliseconds-histogram}

თითოეული tuist გაშვების საერთო ხანგრძლივობა მილიწამებში.

#### ჭდეები {#tuist-runs-duration-miliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `name` | `tuist` ბრძანების სახელი, რომელიც შესრულდა, მაგალითად `build`, `test` და ა.შ. |
| `is_ci` | ბულის მნიშვნელობა, რომელიც მიუთითებს, იყო თუ არა შემსრულებელი CI თუ დეველოპერის მანქანა. |
| `status` | `1` `success`-ის შემთხვევაში, `failure` `0`-ის შემთხვევაში. |

## ქეშის მეტრიკები {#cache-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება Tuist Cache-ს.

### `tuist_cache_events_total` (მრიცხველი) {#tuist_cache_events_total-counter}

ბინარული ქეშის მოვლენების საერთო რაოდენობა.

#### ჭდეები {#tuist-cache-events-total-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `event_type` | შეიძლება იყოს `local_hit`, `remote_hit` ან `miss`. |

### `tuist_cache_uploads_total` (მრიცხველი) {#tuist_cache_uploads_total-counter}

ბინარულ ქეშში ატვირთვების რაოდენობა.

### `tuist_cache_uploaded_bytes` (ჯამი) {#tuist_cache_uploaded_bytes-sum}

ბინარულ ქეშში ატვირთული ბაიტების რაოდენობა.

### `tuist_cache_downloads_total` (მრიცხველი) {#tuist_cache_downloads_total-counter}

ბინარული ქეშიდან ჩამოტვირთვების რაოდენობა.

### `tuist_cache_downloaded_bytes` (ჯამი) {#tuist_cache_downloaded_bytes-sum}

ბინარული ქეშიდან ჩამოტვირთული ბაიტების რაოდენობა.

---

## პრივიუს მეტრიკები {#previews-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება პრივიუს ფუნქციას.

### `tuist_previews_uploads_total` (ჯამი) {#tuist_previews_uploads_total-counter}

ატვირთული პრივიუსების საერთო რაოდენობა.

### `tuist_previews_downloads_total` (ჯამი) {#tuist_previews_downloads_total-counter}

ჩამოტვირთული პრივიუსების საერთო რაოდენობა.

---

## საცავის მეტრიკები {#storage-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება არტიფაქტების შენახვას შორეულ საცავში (მაგ. s3).

> [!TIP]
> ეს მეტრიკები სასარგებლოა საცავის ოპერაციების წარმადობის გასაგებად და პოტენციური „ბოთლneck“-ების გამოსავლენად.


### `tuist_storage_get_object_size_size_bytes` (ჰისტოგრამა) {#tuist_storage_get_object_size_size_bytes-histogram}

შორეული საცავიდან ამოღებული ობიექტის ზომა (ბაიტებში).

#### ჭდეები {#tuist-storage-get-object-size-size-bytes-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_size_duration_miliseconds` (ჰისტოგრამა) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

ობიექტის ზომის შორეული საცავიდან ამოღების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-get-object-size-duration-miliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_size_count` (მრიცხველი) {#tuist_storage_get_object_size_count-counter}

იმ შემთხვევების რაოდენობა, როდესაც ობიექტის ზომა ამოიღეს შორეული საცავიდან.

#### ჭდეები {#tuist-storage-get-object-size-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

ყველა ობიექტის შორეული საცავიდან წაშლის ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის სლაგი, რომლის ობიექტებიც იშლება. |


### `tuist_storage_delete_all_objects_count` (მრიცხველი) {#tuist_storage_delete_all_objects_count-counter}

იმ შემთხვევების რაოდენობა, როდესაც პროექტის ყველა ობიექტი წაიშალა შორეული საცავიდან.

#### ჭდეები {#tuist-storage-delete-all-objects-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `project_slug` | პროექტის სლაგი, რომლის ობიექტებიც იშლება. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

შორეულ საცავში ატვირთვის დაწყების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_start_upload_duration_count` (მრიცხველი) {#tuist_storage_multipart_start_upload_duration_count-counter}

იმ შემთხვევების რაოდენობა, როდესაც შორეულ საცავში ატვირთვა დაიწყო.

#### ჭდეები {#tuist-storage-multipart-start-upload-duration-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

ობიექტის სტრიქონად შორეული საცავიდან ამოღების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_get_object_as_string_count` (რაოდენობა) {#tuist_storage_get_object_as_string_count-count}

იმ შემთხვევების რაოდენობა, როდესაც ობიექტი სტრიქონად ამოიღეს შორეული საცავიდან.

#### ჭდეები {#tuist-storage-get-object-as-string-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |


### `tuist_storage_check_object_existence_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

შორეულ საცავში ობიექტის არსებობის შემოწმების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_check_object_existence_count` (რაოდენობა) {#tuist_storage_check_object_existence_count-count}

იმ შემთხვევების რაოდენობა, როდესაც შორეულ საცავში ობიექტის არსებობა შეამოწმეს.

#### ჭდეები {#tuist-storage-check-object-existence-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

შორეულ საცავში ობიექტისთვის ჩამოსატვირთი წინასწარ ხელმოწერილი URL-ის გენერირების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |


### `tuist_storage_generate_download_presigned_url_count` (რაოდენობა) {#tuist_storage_generate_download_presigned_url_count-count}

იმ შემთხვევების რაოდენობა, როდესაც შორეულ საცავში ობიექტისთვის ჩამოსატვირთი წინასწარ ხელმოწერილი URL შეიქმნა.

#### ჭდეები {#tuist-storage-generate-download-presigned-url-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

შორეულ საცავში ობიექტის ნაწილის ატვირთვის წინასწარ ხელმოწერილი URL-ის გენერირების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (რაოდენობა) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

იმ შემთხვევების რაოდენობა, როდესაც შორეულ საცავში ობიექტის ნაწილის ატვირთვის წინასწარ ხელმოწერილი URL შეიქმნა.

#### ჭდეები {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |
| `part_number` | ატვირთვადი ობიექტის ნაწილის ნომერი. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (ჰისტოგრამა) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

შორეულ საცავში ატვირთვის დასრულების ხანგრძლივობა (მილიწამებში).

#### ჭდეები {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |


### `tuist_storage_multipart_complete_upload_count` (რაოდენობა) {#tuist_storage_multipart_complete_upload_count-count}

იმ შემთხვევების საერთო რაოდენობა, როდესაც შორეულ საცავში ატვირთვა დასრულდა.

#### ჭდეები {#tuist-storage-multipart-complete-upload-count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `object_key` | ობიექტის მოსაძებნი გასაღები შორეულ საცავში. |
| `upload_id` | მრავალნაწილიანი ატვირთვის ID. |

---

## ავტორიზაციის მეტრიკები {#authentication-metrics}

ავტორიზაციასთან დაკავშირებული მეტრიკების ნაკრები.

### `tuist_authentication_token_refresh_error_total` (მრიცხველი) {#tuist_authentication_token_refresh_error_total-counter}

ტოკენის განახლების შეცდომების საერთო რაოდენობა.

#### ჭდეები {#tuist-authentication-token-refresh-error-total-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `cli_version` | Tuist CLI-ის ვერსია, რომელმაც შეცდომა გამოიწვია. |
| `reason` | ტოკენის განახლების შეცდომის მიზეზი, მაგალითად `invalid_token_type` ან `invalid_token`. |

---

## პროექტების მეტრიკები {#projects-metrics}

პროექტებთან დაკავშირებული მეტრიკების ნაკრები.

### `tuist_projects_total` (ბოლო მნიშვნელობა) {#tuist_projects_total-last_value}

პროექტების საერთო რაოდენობა.

---

## ანგარიშების მეტრიკები {#accounts-metrics}

ანგარიშებთან (მომხმარებლები და ორგანიზაციები) დაკავშირებული მეტრიკების ნაკრები.

### `tuist_accounts_organizations_total` (ბოლო მნიშვნელობა) {#tuist_accounts_organizations_total-last_value}

ორგანიზაციების საერთო რაოდენობა.

### `tuist_accounts_users_total` (ბოლო მნიშვნელობა) {#tuist_accounts_users_total-last_value}

მომხმარებლების საერთო რაოდენობა.


## მონაცემთა ბაზის მეტრიკები {#database-metrics}

მონაცემთა ბაზასთან კავშირთან დაკავშირებული მეტრიკების ნაკრები.

რეპოზიტორიის პულის მეტრიკები შიგნით იღება ყოველ 100 მწ-ში და შემდეგ ექსპორტირდება Prometheus-ზე `/metrics`-ზე. ქვემოთ მოცემული `last_value` მეტრიკები აჩვენებს პულის უახლეს მდგომარეობას სკრეიპინგის დროს. წნევის მეტრიკები, რომლებიც ქვემოთაა, არის ჯამები, მიღებული ამ 100 მწ-იანი ნიმუშებიდან, რაც მოკლე გაჯერების ფანჯრების აღმოჩენას ამარტივებს მაშინაც კი, თუ ისინი აღდგებიან შემდეგი სკრეიპინგის წინ.

### `tuist_repo_pool_checkout_queue_length` (ბოლო მნიშვნელობა) {#tuist_repo_pool_checkout_queue_length-last_value}

მონაცემთა ბაზის მოთხოვნების რაოდენობა, რომლებიც რიგში ელოდებიან მონაცემთა ბაზის კავშირთან მიმაგრებას.

#### ჭდეები {#tuist_repo_pool_checkout_queue_length-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_ready_conn_count` (ბოლო მნიშვნელობა) {#tuist_repo_pool_ready_conn_count-last_value}

მონაცემთა ბაზის კავშირების რაოდენობა, რომლებიც მზად არიან მონაცემთა ბაზის მოთხოვნასთან მიმაგრებისთვის.

#### ჭდეები {#tuist_repo_pool_ready_conn_count-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_size` (ბოლო მნიშვნელობა) {#tuist_repo_pool_size-last_value}

პულში კავშირების კონფიგურირებული რაოდენობა.

#### ჭდეები {#tuist_repo_pool_size-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_total_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_total_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების საერთო რაოდენობა (იზრდება 1-ით ყოველ გამოკითხვაზე). გამოიყენეთ ეს როგორც მნიშვნელი დატვირთვის ან შიმშილის პროცენტების გამოთვლისას: `rate(busy_samples) / rate(total_samples)` ან `rate(starved_samples) / rate(total_samples)`.

#### ჭდეები {#tuist_repo_pool_checkout_queue_total_samples_sum-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_observed_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_observed_sum-sum}

რიგში მყოფი checkout მოთხოვნების ჯამი, დაკვირვებული რეპოზიტორიის პულის გამოკითხვების განმავლობაში. ეს სასარგებლოა პულის კონკურენციის მოკლე აფეთქებების აღმოსაჩენად, რომლებიც შესაძლოა არ ჩანდეს მხოლოდ უახლესი რიგის სიგრძის ნიმუშში.

#### ჭდეები {#tuist_repo_pool_checkout_queue_observed_sum-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_busy_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_busy_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების რაოდენობა, სადაც მინიმუმ ერთი მონაცემთა ბაზის checkout მოთხოვნა ელოდებოდა რიგში.

#### ჭდეები {#tuist_repo_pool_checkout_queue_busy_samples_total-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_checkout_queue_starved_samples_sum` (ჯამი) {#tuist_repo_pool_checkout_queue_starved_samples_sum-sum}

რეპოზიტორიის პულის გამოკითხვების რაოდენობა, სადაც checkout მოთხოვნები იყო რიგში და არ იყო ხელმისაწვდომი მზა კავშირები. ამ მაჩვენებლის მუდმივი ზრდა ჩვეულებრივ ნიშნავს, რომ პული გადატვირთულია.

#### ჭდეები {#tuist_repo_pool_checkout_queue_starved_samples_total-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `repo` | რეპოზიტორია, რომელმაც გამოიმუშავა მეტრიკა, მაგალითად `postgres`, `clickhouse_read` ან `clickhouse_write`. |
| `database` | ძირითადი მონაცემთა ბაზის ტიპი, მაგალითად `postgres` ან `clickhouse`. |

### `tuist_repo_pool_db_connection_connected` (მრიცხველი) {#tuist_repo_pool_db_connection_connected-counter}

მონაცემთა ბაზასთან დამყარებული კავშირების რაოდენობა.

### `tuist_repo_pool_db_connection_disconnected` (მრიცხველი) {#tuist_repo_pool_db_connection_disconnected-counter}

მონაცემთა ბაზიდან გაწყვეტილი კავშირების რაოდენობა.

#### ჭდეები {#tuist_repo_pool_db_connection_connected_and_disconnected-tags}

| ჭდე | აღწერა |
|--- | ---- |
| `tag` | DBConnection-ის მოსმენის ჭდე, რომელიც აიდენტიფიცირებს გამომუშავებელ რეპოზიტორიას. |

## HTTP მეტრიკები {#http-metrics}

მეტრიკების ნაკრები, რომელიც უკავშირდება Tuist-ის ურთიერთქმედებას სხვა სერვისებთან HTTP-ის საშუალებით.

### `tuist_http_request_count` (მრიცხველი) {#tuist_http_request_count-last_value}

გამავალი HTTP მოთხოვნების რაოდენობა.

### `tuist_http_request_duration_nanoseconds_sum` (ჯამი) {#tuist_http_request_duration_nanoseconds_sum-last_value}

გამავალი მოთხოვნების ხანგრძლივობის ჯამი (მათ შორის დრო, რომელიც მათ დასჭირდათ კავშირზე მინიჭების მოლოდინში).

### `tuist_http_request_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_request_duration_nanoseconds_bucket-distribution}
გამავალი მოთხოვნების ხანგრძლივობის განაწილება (მათ შორის დრო, რომელიც მათ დასჭირდათ კავშირზე მინიჭების მოლოდინში).

### `tuist_http_queue_count` (მრიცხველი) {#tuist_http_queue_count-counter}

პულიდან მიღებული მოთხოვნების რაოდენობა.

### `tuist_http_queue_duration_nanoseconds_sum` (ჯამი) {#tuist_http_queue_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება კავშირის მიღებას პულიდან.

### `tuist_http_queue_idle_time_nanoseconds_sum` (ჯამი) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდებოდა მიღებას.

### `tuist_http_queue_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

დრო, რომელიც სჭირდება კავშირის მიღებას პულიდან.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (განაწილება) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

დრო, როდესაც კავშირი იყო თავისუფალი და ელოდებოდა მიღებას.

### `tuist_http_connection_count` (მრიცხველი) {#tuist_http_connection_count-counter}

დამყარებული კავშირების რაოდენობა.

### `tuist_http_connection_duration_nanoseconds_sum` (ჯამი) {#tuist_http_connection_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება ჰოსტთან კავშირის დამყარებას.

### `tuist_http_connection_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

ჰოსტთან კავშირის დამყარებისთვის საჭირო დროის განაწილება.

### `tuist_http_send_count` (მრიცხველი) {#tuist_http_send_count-counter}

მოთხოვნების რაოდენობა, რომლებიც გაიგზავნა პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_send_duration_nanoseconds_sum` (ჯამი) {#tuist_http_send_duration_nanoseconds_sum-sum}

დრო, რომელიც სჭირდება მოთხოვნების დასრულებას პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_send_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

მოთხოვნების დასრულებისთვის საჭირო დროის განაწილება პულიდან კავშირზე მინიჭების შემდეგ.

### `tuist_http_receive_count` (მრიცხველი) {#tuist_http_receive_count-counter}

გაგზავნილი მოთხოვნებიდან მიღებული პასუხების რაოდენობა.

### `tuist_http_receive_duration_nanoseconds_sum` (ჯამი) {#tuist_http_receive_duration_nanoseconds_sum-sum}

პასუხების მიღებაზე დახარჯული დრო.

### `tuist_http_receive_duration_nanoseconds_bucket` (განაწილება) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

პასუხების მიღებაზე დახარჯული დროის განაწილება.

### `tuist_http_queue_available_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_available_connections-last_value}

რიგში ხელმისაწვდომი კავშირების რაოდენობა.

### `tuist_http_queue_in_use_connections` (ბოლო მნიშვნელობა) {#tuist_http_queue_in_use_connections-last_value}

რიგში გამოყენებაში მყოფი კავშირების რაოდენობა.
