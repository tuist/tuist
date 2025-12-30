---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetria {#telemetry}

Metryki zebrane przez serwer Tuist można pozyskać za pomocą
[Prometheus](https://prometheus.io/) i narzędzia do wizualizacji, takiego jak
[Grafana](https://grafana.com/), aby utworzyć niestandardowy pulpit nawigacyjny
dostosowany do własnych potrzeb. Metryki Prometheus są obsługiwane przez punkt
końcowy `/metrics` na porcie 9091. Interwał
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
Prometheusa powinien być ustawiony na mniej niż 10_000 sekund (zalecamy
zachowanie domyślnej wartości 15 sekund).

## Analityka PostHog {#posthog-analytics}

Tuist integruje się z [PostHog](https://posthog.com/) w celu analizy zachowań
użytkowników i śledzenia zdarzeń. Pozwala to zrozumieć, w jaki sposób
użytkownicy wchodzą w interakcję z serwerem Tuist, śledzić wykorzystanie funkcji
i uzyskać wgląd w zachowanie użytkowników w witrynie marketingowej, pulpicie
nawigacyjnym i dokumentacji API.

### Konfiguracja {#posthog-configuration}

Integracja PostHog jest opcjonalna i można ją włączyć poprzez ustawienie
odpowiednich zmiennych środowiskowych. Po skonfigurowaniu Tuist będzie
automatycznie śledzić zdarzenia użytkowników, wyświetlenia stron i podróże
użytkowników.

| Zmienna środowiskowa    | Opis                                              | Wymagane | Domyślne | Przykłady                                         |
| ----------------------- | ------------------------------------------------- | -------- | -------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Klucz API projektu PostHog                        | Nie      |          | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | Adres URL punktu końcowego interfejsu API PostHog | Nie      |          | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analityka jest włączona tylko wtedy, gdy zarówno `TUIST_POSTHOG_API_KEY` i
`TUIST_POSTHOG_URL` są skonfigurowane. W przypadku braku którejkolwiek z tych
zmiennych zdarzenia analityczne nie będą wysyłane.
<!-- -->
:::

### Cechy {#posthog-features}

Gdy PostHog jest włączony, Tuist automatycznie śledzi:

- **Identyfikacja użytkownika**: Użytkownicy są identyfikowani za pomocą
  unikalnego identyfikatora i adresu e-mail.
- **Aliasowanie użytkowników**: Użytkownicy są przypisywani do nazwy konta w
  celu łatwiejszej identyfikacji.
- **Analityka grupowa**: Użytkownicy są grupowani według wybranego projektu i
  organizacji w celu analizy segmentowej.
- **Sekcje strony**: Zdarzenia zawierają super właściwości wskazujące, która
  sekcja aplikacji je wygenerowała:
  - `marketing` - Wydarzenia ze stron marketingowych i treści publicznych
  - `dashboard` - zdarzenia z głównego pulpitu aplikacji i obszarów
    uwierzytelnionych
  - `api-docs` - Zdarzenia ze stron dokumentacji API
- **Odsłony**: Automatyczne śledzenie nawigacji na stronie przy użyciu Phoenix
  LiveView
- **Zdarzenia niestandardowe**: Zdarzenia specyficzne dla aplikacji dla użycia
  funkcji i interakcji użytkownika

### Kwestie prywatności {#posthog-privacy}

- W przypadku uwierzytelnionych użytkowników PostHog używa unikalnego
  identyfikatora użytkownika jako odrębnego identyfikatora i zawiera jego adres
  e-mail
- W przypadku anonimowych użytkowników PostHog używa trwałości tylko w pamięci,
  aby uniknąć przechowywania danych lokalnie
- Wszystkie analizy szanują prywatność użytkowników i przestrzegają najlepszych
  praktyk w zakresie ochrony danych.
- Dane PostHog są przetwarzane zgodnie z polityką prywatności PostHog i
  konfiguracją użytkownika

## Metryki Elixir {#elixir-metrics}

Domyślnie uwzględniamy metryki środowiska uruchomieniowego Elixir, BEAM, Elixir
i niektórych używanych przez nas bibliotek. Poniżej znajdują się niektóre z
metryk, których można się spodziewać:

- [Aplikacja](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Zalecamy sprawdzenie tych stron, aby dowiedzieć się, które metryki są dostępne i
jak z nich korzystać.

## Wskaźniki przebiegu {#runs-metrics}

Zestaw wskaźników związanych z Tuist Runs.

### `tuist_runs_total` (licznik) {#tuist_runs_total-counter}

Całkowita liczba uruchomień Tuist.

#### Tagi {#tuist-runs-total-tags}

| Tag      | Opis                                                                              |
| -------- | --------------------------------------------------------------------------------- |
| `nazwa`  | Nazwa polecenia `tuist`, które zostało uruchomione, np. `build`, `test`, itp.     |
| `is_ci`  | Wartość logiczna wskazująca, czy executor był maszyną CI, czy maszyną dewelopera. |
| `status` | `0` w przypadku `powodzenia`, `1` w przypadku `niepowodzenia`.                    |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Całkowity czas trwania każdego uruchomienia tuist w milisekundach.

#### Tagi {#tuist-runs-duration-miliseconds-tags}

| Tag      | Opis                                                                              |
| -------- | --------------------------------------------------------------------------------- |
| `nazwa`  | Nazwa polecenia `tuist`, które zostało uruchomione, np. `build`, `test`, itp.     |
| `is_ci`  | Wartość logiczna wskazująca, czy executor był maszyną CI, czy maszyną dewelopera. |
| `status` | `0` w przypadku `powodzenia`, `1` w przypadku `niepowodzenia`.                    |

## Metryki pamięci podręcznej {#cache-metrics}

Zestaw metryk związanych z Tuist Cache.

### `tuist_cache_events_total` (licznik) {#tuist_cache_events_total-counter}

Całkowita liczba zdarzeń binarnej pamięci podręcznej.

#### Tagi {#tuist-cache-events-total-tags}

| Tag          | Opis                                                     |
| ------------ | -------------------------------------------------------- |
| `event_type` | Może być jednym z `local_hit`, `remote_hit`, lub `miss`. |

### `tuist_cache_uploads_total` (licznik) {#tuist_cache_uploads_total-counter}

Liczba załadowań do binarnej pamięci podręcznej.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

Liczba bajtów przesłanych do binarnej pamięci podręcznej.

### `tuist_cache_downloads_total` (licznik) {#tuist_cache_downloads_total-counter}

Liczba pobrań do binarnej pamięci podręcznej.

### `tuist_cache_downloaded_bytes` (sum) {#tuist_cache_downloaded_bytes-sum}

Liczba bajtów pobranych z binarnej pamięci podręcznej.

---

## Wskaźniki podglądu {#previews-metrics}

Zestaw metryk związanych z funkcją podglądu.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

Całkowita liczba przesłanych podglądów.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

Całkowita liczba pobranych podglądów.

---

## Metryki pamięci masowej {#storage-metrics}

Zestaw metryk związanych z przechowywaniem artefaktów w zdalnej pamięci masowej
(np. s3).

::: napiwek
<!-- -->
Metryki te są przydatne do zrozumienia wydajności operacji pamięci masowej i
zidentyfikowania potencjalnych wąskich gardeł.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Rozmiar (w bajtach) obiektu pobranego ze zdalnej pamięci masowej.

#### Tagi {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Czas (w milisekundach) pobierania rozmiaru obiektu ze zdalnej pamięci masowej.

#### Tagi {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |


### `tuist_storage_get_object_size_count` (counter) {#tuist_storage_get_object_size_count-counter}

Liczba pobrań rozmiaru obiektu ze zdalnej pamięci masowej.

#### Tagi {#tuist-storage-get-object-size-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Czas trwania (w milisekundach) usuwania wszystkich obiektów ze zdalnej pamięci
masowej.

#### Tagi {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | Opis                                       |
| -------------- | ------------------------------------------ |
| `project_slug` | Slug projektu, którego obiekty są usuwane. |


### `tuist_storage_delete_all_objects_count` (counter) {#tuist_storage_delete_all_objects_count-counter}

Liczba przypadków usunięcia wszystkich obiektów projektu ze zdalnej pamięci
masowej.

#### Tagi {#tuist-storage-delete-all-objects-count-tags}

| Tag            | Opis                                       |
| -------------- | ------------------------------------------ |
| `project_slug` | Slug projektu, którego obiekty są usuwane. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Czas trwania (w milisekundach) rozpoczęcia przesyłania do zdalnej pamięci
masowej.

#### Tagi {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_multipart_start_upload_duration_count` (counter) {#tuist_storage_multipart_start_upload_duration_count-counter}

Liczba przypadków rozpoczęcia przesyłania do zdalnej pamięci masowej.

#### Tagi {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Czas (w milisekundach) pobierania obiektu jako ciągu znaków ze zdalnej pamięci
masowej.

#### Tagi {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Liczba przypadków, w których obiekt został pobrany jako ciąg znaków ze zdalnej
pamięci masowej.

#### Tagi {#tuist-storage-get-object-as-string-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Czas trwania (w milisekundach) sprawdzania istnienia obiektu w zdalnej pamięci
masowej.

#### Tagi {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Liczba sprawdzeń istnienia obiektu w zdalnej pamięci masowej.

#### Tagi {#tuist-storage-check-object-existence-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Czas trwania (w milisekundach) generowania adresu URL z podpisem pobierania dla
obiektu w zdalnym magazynie.

#### Tagi {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Liczba przypadków wygenerowania adresu URL z podpisem pobierania dla obiektu w
zdalnej pamięci masowej.

#### Tagi {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Czas trwania (w milisekundach) generowania adresu URL z podpisem przesyłania
części dla obiektu w zdalnym magazynie.

#### Tagi {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag           | Opis                                                  |
| ------------- | ----------------------------------------------------- |
| `object_key`  | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |
| `part_number` | Numer części przesyłanego obiektu.                    |
| `upload_id`   | Identyfikator przesyłania wieloczęściowego.           |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Liczba przypadków wygenerowania adresu URL z podpisem przesyłania części dla
obiektu w zdalnym magazynie.

#### Tagi {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag           | Opis                                                  |
| ------------- | ----------------------------------------------------- |
| `object_key`  | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |
| `part_number` | Numer części przesyłanego obiektu.                    |
| `upload_id`   | Identyfikator przesyłania wieloczęściowego.           |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Czas trwania (w milisekundach) przesyłania do zdalnej pamięci masowej.

#### Tagi {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |
| `upload_id`  | Identyfikator przesyłania wieloczęściowego.           |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Całkowita liczba przypadków przesłania danych do zdalnej pamięci masowej.

#### Tagi {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | Opis                                                  |
| ------------ | ----------------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci masowej. |
| `upload_id`  | Identyfikator przesyłania wieloczęściowego.           |

---

## Metryki uwierzytelniania {#authentication-metrics}

Zestaw metryk związanych z uwierzytelnianiem.

### `tuist_authentication_token_refresh_error_total` (licznik) {#tuist_authentication_token_refresh_error_total-counter}

Całkowita liczba błędów odświeżania tokenów.

#### Tagi {#tuist-authentication-token-refresh-error-total-tags}

| Tag           | Opis                                                                               |
| ------------- | ---------------------------------------------------------------------------------- |
| `cli_version` | Wersja interfejsu Tuist CLI, w której wystąpił błąd.                               |
| `powód`       | Powód błędu odświeżenia tokena, taki jak `invalid_token_type` lub `invalid_token`. |

---

## Metryki projektów {#projects-metrics}

Zestaw wskaźników związanych z projektami.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

Całkowita liczba projektów.

---

## Metryki kont {#accounts-metrics}

Zestaw metryk związanych z kontami (użytkownikami i organizacjami).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

Całkowita liczba organizacji.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

Całkowita liczba użytkowników.


## Metryki bazy danych {#database-metrics}

Zestaw metryk związanych z połączeniem z bazą danych.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Liczba zapytań do bazy danych znajdujących się w kolejce oczekujących na
przypisanie do połączenia z bazą danych.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Liczba połączeń z bazą danych, które są gotowe do przypisania do zapytania bazy
danych.


### `tuist_repo_pool_db_connection_connected` (licznik) {#tuist_repo_pool_db_connection_connected-counter}

Liczba połączeń nawiązanych z bazą danych.

### `tuist_repo_pool_db_connection_disconnected` (licznik) {#tuist_repo_pool_db_connection_disconnected-counter}

Liczba połączeń, które zostały rozłączone z bazą danych.

## Metryki HTTP {#http-metrics}

Zestaw metryk związanych z interakcjami Tuist z innymi usługami za pośrednictwem
protokołu HTTP.

### `tuist_http_request_count` (licznik) {#tuist_http_request_count-last_value}

Liczba wychodzących żądań HTTP.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

Suma czasu trwania żądań wychodzących (w tym czasu oczekiwania na przypisanie do
połączenia).

### `tuist_http_request_duration_nanosecond_bucket` (dystrybucja) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Rozkład czasu trwania żądań wychodzących (w tym czasu oczekiwania na przypisanie
do połączenia).

### `tuist_http_queue_count` (licznik) {#tuist_http_queue_count-counter}

Liczba żądań, które zostały pobrane z puli.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Czas pobierania połączenia z puli.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Czas bezczynności połączenia w oczekiwaniu na odzyskanie.

### `tuist_http_queue_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Czas pobierania połączenia z puli.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dystrybucja) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Czas bezczynności połączenia w oczekiwaniu na odzyskanie.

### `tuist_http_connection_count` (licznik) {#tuist_http_connection_count-counter}

Liczba nawiązanych połączeń.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Czas potrzebny do nawiązania połączenia z hostem.

### `tuist_http_connection_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Rozkład czasu potrzebnego do nawiązania połączenia z hostem.

### `tuist_http_send_count` (licznik) {#tuist_http_send_count-counter}

Liczba żądań, które zostały wysłane po przypisaniu do połączenia z puli.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

Czas potrzebny na ukończenie żądań po przypisaniu do połączenia z puli.

### `tuist_http_send_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Rozkład czasu potrzebnego na ukończenie żądań po przypisaniu do połączenia z
puli.

### `tuist_http_receive_count` (licznik) {#tuist_http_receive_count-counter}

Liczba otrzymanych odpowiedzi na wysłane żądania.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Czas spędzony na otrzymywaniu odpowiedzi.

### `tuist_http_receive_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Rozkład czasu spędzonego na otrzymywaniu odpowiedzi.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Liczba połączeń dostępnych w kolejce.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Liczba używanych połączeń kolejki.
