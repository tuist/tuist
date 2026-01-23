---
{
  "title": "Telemetry",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Monitor your Tuist server with Prometheus and Grafana telemetry."
}
---
# Telemetria {#telemetry}

Możesz pobrać metryki zebrane przez serwer Tuist za pomocą
[Prometheus](https://prometheus.io/) i narzędzia do wizualizacji, takiego jak
[Grafana](https://grafana.com/), aby stworzyć niestandardowy pulpit nawigacyjny
dostosowany do swoich potrzeb. Metryki Prometheus są udostępniane za
pośrednictwem punktu końcowego `/metrics` na porcie 9091. Prometheus
[scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus)
powinien być ustawiony na mniej niż 10_000 sekund (zalecamy pozostawienie
domyślnego ustawienia 15 sekund).

## Analizy PostHog {#posthog-analytics}

Tuist integruje się z [PostHog](https://posthog.com/) w celu analizy zachowań
użytkowników i śledzenia zdarzeń. Pozwala to zrozumieć, w jaki sposób
użytkownicy wchodzą w interakcję z serwerem Tuist, śledzić wykorzystanie funkcji
i uzyskać wgląd w zachowania użytkowników w witrynie marketingowej, panelu
nawigacyjnym i dokumentacji API.

### Konfiguracja {#posthog-configuration}

Integracja z PostHog jest opcjonalna i można ją włączyć, ustawiając odpowiednie
zmienne środowiskowe. Po skonfigurowaniu Tuist będzie automatycznie śledzić
zdarzenia użytkowników, wyświetlenia stron i ścieżki użytkowników.

| Zmienna środowiskowa    | Opis                                   | Wymagane | Domyślne | Przykłady                                         |
| ----------------------- | -------------------------------------- | -------- | -------- | ------------------------------------------------- |
| `TUIST_POSTHOG_API_KEY` | Twój klucz API projektu PostHog        | Nie      |          | `phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR` |
| `TUIST_POSTHOG_URL`     | Adres URL punktu końcowego API PostHog | Nie      |          | `https://eu.i.posthog.com`                        |

::: info ANALYTICS ENABLEMENT
<!-- -->
Analizy są włączone tylko wtedy, gdy skonfigurowane są zarówno
`TUIST_POSTHOG_API_KEY`, jak i `TUIST_POSTHOG_URL`. Jeśli brakuje którejkolwiek
z tych zmiennych, żadne zdarzenia analityczne nie będą wysyłane.
<!-- -->
:::

### Funkcje {#posthog-features}

Gdy PostHog jest włączony, Tuist automatycznie śledzi:

- **Identyfikacja użytkownika**: Użytkownicy są identyfikowani na podstawie
  unikalnego identyfikatora i adresu e-mail.
- **Aliasy użytkowników**: Użytkownicy otrzymują aliasy na podstawie nazwy
  swojego konta, aby ułatwić ich identyfikację.
- **Analiza grupowa**: Użytkownicy są grupowani według wybranego projektu i
  organizacji w celu przeprowadzenia analizy segmentowej.
- **Sekcje strony**: Zdarzenia zawierają superwłaściwości wskazujące, która
  sekcja aplikacji je wygenerowała:
  - `marketing` - Wydarzenia ze stron marketingowych i treści publicznych
  - `dashboard` - Wydarzenia z głównego pulpitu aplikacji i obszarów
    uwierzytelnionych
  - `api-docs` - Zdarzenia ze stron dokumentacji API
- **Wyświetlenia strony**: Automatyczne śledzenie nawigacji po stronie za pomocą
  Phoenix LiveView
- **Zdarzenia niestandardowe**: Zdarzenia specyficzne dla aplikacji dotyczące
  korzystania z funkcji i interakcji użytkownika.

### Kwestie dotyczące prywatności {#posthog-privacy}

- W przypadku uwierzytelnionych użytkowników PostHog wykorzystuje unikalny
  identyfikator użytkownika jako odrębny identyfikator i dołącza jego adres
  e-mail.
- W przypadku anonimowych użytkowników PostHog wykorzystuje pamięć tylko do
  przechowywania danych, aby uniknąć lokalnego przechowywania danych.
- Wszystkie analizy respektują prywatność użytkowników i są zgodne z najlepszymi
  praktykami w zakresie ochrony danych.
- Dane PostHog są przetwarzane zgodnie z polityką prywatności PostHog i
  konfiguracją użytkownika.

## Metryki Elixir {#elixir-metrics}

Domyślnie uwzględniamy metryki środowiska uruchomieniowego Elixir, BEAM, Elixir
oraz niektórych bibliotek, z których korzystamy. Poniżej przedstawiono niektóre
z metryk, których można się spodziewać:

- [Aplikacja](https://hexdocs.pm/prom_ex/PromEx.Plugins.Application.html)
- [BEAM](https://hexdocs.pm/prom_ex/PromEx.Plugins.Beam.html)
- [Phoenix](https://hexdocs.pm/prom_ex/PromEx.Plugins.Phoenix.html)
- [Phoenix
  LiveView](https://hexdocs.pm/prom_ex/PromEx.Plugins.PhoenixLiveView.html)
- [Ecto](https://hexdocs.pm/prom_ex/PromEx.Plugins.Ecto.html)
- [Oban](https://hexdocs.pm/prom_ex/PromEx.Plugins.Oban.html)

Zalecamy zapoznanie się z tymi stronami, aby dowiedzieć się, jakie wskaźniki są
dostępne i jak z nich korzystać.

## Metryki uruchomień {#runs-metrics}

Zestaw wskaźników związanych z Tuist Runs.

### `tuist_runs_total` (licznik) {#tuist_runs_total-counter}

Łączna liczba Tuist Runs.

#### Tagi {#tuist-runs-total-tags}

| Tag      | Opis                                                                         |
| -------- | ---------------------------------------------------------------------------- |
| `nazwa`  | Nazwa uruchomionego polecenia `tuist`, np. `build`, `test` itp.              |
| `is_ci`  | Wartość logiczna wskazująca, czy wykonawcą był CI, czy komputer programisty. |
| `status` | `0` w przypadku sukcesu `` , `1` w przypadku niepowodzenia `` .              |

### `tuist_runs_duration_milliseconds` (histogram) {#tuist_runs_duration_milliseconds-histogram}

Całkowity czas trwania każdego przebiegu tuist w milisekundach.

#### Tagi {#tuist-runs-duration-miliseconds-tags}

| Tag      | Opis                                                                         |
| -------- | ---------------------------------------------------------------------------- |
| `nazwa`  | Nazwa uruchomionego polecenia `tuist`, np. `build`, `test` itp.              |
| `is_ci`  | Wartość logiczna wskazująca, czy wykonawcą był CI, czy komputer programisty. |
| `status` | `0` w przypadku sukcesu `` , `1` w przypadku niepowodzenia `` .              |

## Metryki pamięci podręcznej {#cache-metrics}

Zestaw wskaźników związanych z pamięcią podręczną Tuist.

### `tuist_cache_events_total` (licznik) {#tuist_cache_events_total-counter}

Całkowita liczba zdarzeń pamięci podręcznej binarnej.

#### Tagi {#tuist-cache-events-total-tags}

| Tag          | Opis                                                                     |
| ------------ | ------------------------------------------------------------------------ |
| `event_type` | Może to być jedno z następujących: `local_hit`, `remote_hit` lub `miss`. |

### `tuist_cache_uploads_total` (licznik) {#tuist_cache_uploads_total-counter}

Liczba przesłanych plików do pamięci podręcznej plików binarnych.

### `tuist_cache_uploaded_bytes` (sum) {#tuist_cache_uploaded_bytes-sum}

Liczba bajtów przesłanych do pamięci podręcznej plików binarnych.

### `tuist_cache_downloads_total` (licznik) {#tuist_cache_downloads_total-counter}

Liczba pobrań do pamięci podręcznej plików binarnych.

### `tuist_cache_downloaded_bytes` (suma) {#tuist_cache_downloaded_bytes-sum}

Liczba bajtów pobranych z pamięci podręcznej plików binarnych.

---

## Wskaźniki podglądu {#previews-metrics}

Zestaw wskaźników związanych z funkcją podglądu.

### `tuist_previews_uploads_total` (sum) {#tuist_previews_uploads_total-counter}

Łączna liczba przesłanych podglądów.

### `tuist_previews_downloads_total` (sum) {#tuist_previews_downloads_total-counter}

Łączna liczba pobranych podglądów.

---

## Wskaźniki pamięci masowej {#storage-metrics}

Zestaw wskaźników związanych z przechowywaniem artefaktów w zdalnej pamięci
masowej (np. s3).

::: napiwek
<!-- -->
Wskaźniki te są przydatne do zrozumienia wydajności operacji przechowywania
danych i identyfikacji potencjalnych wąskich gardeł.
<!-- -->
:::

### `tuist_storage_get_object_size_size_bytes` (histogram) {#tuist_storage_get_object_size_size_bytes-histogram}

Rozmiar (w bajtach) obiektu pobranego ze zdalnej pamięci.

#### Tagi {#tuist-storage-get-object-size-size-bytes-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |


### `tuist_storage_get_object_size_duration_miliseconds` (histogram) {#tuist_storage_get_object_size_duration_miliseconds-histogram}

Czas (w milisekundach) pobierania rozmiaru obiektu ze zdalnej pamięci.

#### Tagi {#tuist-storage-get-object-size-duration-miliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |


### `tuist_storage_get_object_size_count` (licznik) {#tuist_storage_get_object_size_count-counter}

Liczba pobrań rozmiaru obiektu z pamięci zdalnej.

#### Tagi {#tuist-storage-get-object-size-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_delete_all_objects_duration_milliseconds` (histogram) {#tuist_storage_delete_all_objects_duration_milliseconds-histogram}

Czas trwania (w milisekundach) usuwania wszystkich obiektów ze zdalnej pamięci.

#### Tagi {#tuist-storage-delete-all-objects-duration-milliseconds-tags}

| Tag            | Opis                                        |
| -------------- | ------------------------------------------- |
| `project_slug` | Nazwa projektu, którego obiekty są usuwane. |


### `tuist_storage_delete_all_objects_count` (licznik) {#tuist_storage_delete_all_objects_count-counter}

Liczba przypadków usunięcia wszystkich obiektów projektu z pamięci zdalnej.

#### Tagi {#tuist-storage-delete-all-objects-count-tags}

| Tag            | Opis                                        |
| -------------- | ------------------------------------------- |
| `project_slug` | Nazwa projektu, którego obiekty są usuwane. |


### `tuist_storage_multipart_start_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_start_upload_duration_milliseconds-histogram}

Czas trwania (w milisekundach) rozpoczęcia przesyłania do zdalnej pamięci.

#### Tagi {#tuist-storage-multipart-start-upload-duration-milliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_multipart_start_upload_duration_count` (licznik) {#tuist_storage_multipart_start_upload_duration_count-counter}

Liczba przypadków rozpoczęcia przesyłania do zdalnej pamięci masowej.

#### Tagi {#tuist-storage-multipart-start-upload-duration-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |


### `tuist_storage_get_object_as_string_duration_milliseconds` (histogram) {#tuist_storage_get_object_as_string_duration_milliseconds-histogram}

Czas (w milisekundach) pobierania obiektu jako ciągu znaków ze zdalnej pamięci.

#### Tagi {#tuist-storage-get-object-as-string-duration-milliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_get_object_as_string_count` (count) {#tuist_storage_get_object_as_string_count-count}

Liczba pobrań obiektu jako ciągu znaków z pamięci zdalnej.

#### Tagi {#tuist-storage-get-object-as-string-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |


### `tuist_storage_check_object_existence_duration_milliseconds` (histogram) {#tuist_storage_check_object_existence_duration_milliseconds-histogram}

Czas (w milisekundach) sprawdzania istnienia obiektu w zdalnej pamięci.

#### Tagi {#tuist-storage-check-object-existence-duration-milliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_check_object_existence_count` (count) {#tuist_storage_check_object_existence_count-count}

Liczba sprawdzeń istnienia obiektu w zdalnej pamięci.

#### Tagi {#tuist-storage-check-object-existence-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_generate_download_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_generate_download_presigned_url_duration_milliseconds-histogram}

Czas (w milisekundach) generowania wstępnie podpisanego adresu URL do pobrania
obiektu w zdalnej pamięci.

#### Tagi {#tuist-storage-generate-download-presigned-url-duration-milliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |


### `tuist_storage_generate_download_presigned_url_count` (count) {#tuist_storage_generate_download_presigned_url_count-count}

Liczba przypadków wygenerowania wstępnie podpisanego adresu URL do pobrania dla
obiektu w zdalnej pamięci.

#### Tagi {#tuist-storage-generate-download-presigned-url-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |

### `tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds` (histogram) {#tuist_storage_multipart_generate_upload_part_presigned_url_duration_milliseconds-histogram}

Czas (w milisekundach) generowania częściowo przesłanego adresu URL z podpisem
dla obiektu w zdalnej pamięci.

#### Tagi {#tuist-storage-multipart-generate-upload-part-presigned-url-duration-milliseconds-tags}

| Tag            | Opis                                          |
| -------------- | --------------------------------------------- |
| `object_key`   | Klucz wyszukiwania obiektu w zdalnej pamięci. |
| `numer_części` | Numer części obiektu, który jest przesyłany.  |
| `upload_id`    | Identyfikator przesyłania wieloczęściowego.   |

### `tuist_storage_multipart_generate_upload_part_presigned_url_count` (count) {#tuist_storage_multipart_generate_upload_part_presigned_url_count-count}

Liczba wygenerowanych częściowo przesłanych adresów URL dla obiektu w zdalnej
pamięci masowej.

#### Tagi {#tuist-storage-multipart-generate-upload-part-presigned-url-count-tags}

| Tag            | Opis                                          |
| -------------- | --------------------------------------------- |
| `object_key`   | Klucz wyszukiwania obiektu w zdalnej pamięci. |
| `numer_części` | Numer części obiektu, który jest przesyłany.  |
| `upload_id`    | Identyfikator przesyłania wieloczęściowego.   |

### `tuist_storage_multipart_complete_upload_duration_milliseconds` (histogram) {#tuist_storage_multipart_complete_upload_duration_milliseconds-histogram}

Czas (w milisekundach) potrzebny do zakończenia przesyłania do zdalnej pamięci.

#### Tagi {#tuist-storage-multipart-complete-upload-duration-milliseconds-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |
| `upload_id`  | Identyfikator przesyłania wieloczęściowego.   |


### `tuist_storage_multipart_complete_upload_count` (count) {#tuist_storage_multipart_complete_upload_count-count}

Łączna liczba zakończonych operacji przesyłania do zdalnej pamięci masowej.

#### Tagi {#tuist-storage-multipart-complete-upload-count-tags}

| Tag          | Opis                                          |
| ------------ | --------------------------------------------- |
| `object_key` | Klucz wyszukiwania obiektu w zdalnej pamięci. |
| `upload_id`  | Identyfikator przesyłania wieloczęściowego.   |

---

## Wskaźniki uwierzytelniania {#authentication-metrics}

Zestaw wskaźników związanych z uwierzytelnianiem.

### `tuist_authentication_token_refresh_error_total` (licznik) {#tuist_authentication_token_refresh_error_total-counter}

Łączna liczba błędów odświeżania tokenów.

#### Tagi {#tuist-authentication-token-refresh-error-total-tags}

| Tag           | Opis                                                                                      |
| ------------- | ----------------------------------------------------------------------------------------- |
| `cli_version` | Wersja Tuist CLI, w której wystąpił błąd.                                                 |
| `powód`       | Przyczyną błędu odświeżania tokenu może być np. `invalid_token_type` lub `invalid_token`. |

---

## Wskaźniki projektów {#projects-metrics}

Zestaw wskaźników związanych z projektami.

### `tuist_projects_total` (last_value) {#tuist_projects_total-last_value}

Łączna liczba projektów.

---

## Wskaźniki dotyczące kont {#accounts-metrics}

Zestaw wskaźników związanych z kontami (użytkownikami i organizacjami).

### `tuist_accounts_organizations_total` (last_value) {#tuist_accounts_organizations_total-last_value}

Łączna liczba organizacji.

### `tuist_accounts_users_total` (last_value) {#tuist_accounts_users_total-last_value}

Całkowita liczba użytkowników.


## Metryki bazy danych {#database-metrics}

Zestaw wskaźników związanych z połączeniem z bazą danych.

### `tuist_repo_pool_checkout_queue_length` (last_value) {#tuist_repo_pool_checkout_queue_length-last_value}

Liczba zapytań do bazy danych, które znajdują się w kolejce i czekają na
przypisanie do połączenia z bazą danych.

### `tuist_repo_pool_ready_conn_count` (last_value) {#tuist_repo_pool_ready_conn_count-last_value}

Liczba połączeń z bazą danych, które są gotowe do przypisania do zapytania do
bazy danych.


### `tuist_repo_pool_db_connection_connected` (licznik) {#tuist_repo_pool_db_connection_connected-counter}

Liczba połączeń, które zostały nawiązane z bazą danych.

### `tuist_repo_pool_db_connection_disconnected` (licznik) {#tuist_repo_pool_db_connection_disconnected-counter}

Liczba połączeń, które zostały rozłączone z bazą danych.

## Metryki HTTP {#http-metrics}

Zestaw wskaźników związanych z interakcjami Tuist z innymi usługami za
pośrednictwem protokołu HTTP.

### `tuist_http_request_count` (licznik) {#tuist_http_request_count-last_value}

Liczba wychodzących żądań HTTP.

### `tuist_http_request_duration_nanosecond_sum` (sum) {#tuist_http_request_duration_nanosecond_sum-last_value}

Suma czasu trwania wychodzących żądań (w tym czasu oczekiwania na przypisanie do
połączenia).

### `tuist_http_request_duration_nanosecond_bucket` (dystrybucja) {#tuist_http_request_duration_nanosecond_bucket-distribution}
Rozkład czasu trwania wychodzących żądań (w tym czasu oczekiwania na przypisanie
do połączenia).

### `tuist_http_queue_count` (licznik) {#tuist_http_queue_count-counter}

Liczba żądań pobranych z puli.

### `tuist_http_queue_duration_nanoseconds_sum` (sum) {#tuist_http_queue_duration_nanoseconds_sum-sum}

Czas potrzebny do pobrania połączenia z puli.

### `tuist_http_queue_idle_time_nanoseconds_sum` (sum) {#tuist_http_queue_idle_time_nanoseconds_sum-sum}

Czas, przez jaki połączenie pozostawało nieaktywne w oczekiwaniu na pobranie
danych.

### `tuist_http_queue_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_queue_duration_nanoseconds_bucket-distribution}

Czas potrzebny do pobrania połączenia z puli.

### `tuist_http_queue_idle_time_nanoseconds_bucket` (dystrybucja) {#tuist_http_queue_idle_time_nanoseconds_bucket-distribution}

Czas, przez jaki połączenie pozostawało nieaktywne w oczekiwaniu na pobranie
danych.

### `tuist_http_connection_count` (licznik) {#tuist_http_connection_count-counter}

Liczba nawiązanych połączeń.

### `tuist_http_connection_duration_nanoseconds_sum` (sum) {#tuist_http_connection_duration_nanoseconds_sum-sum}

Czas potrzebny do nawiązania połączenia z hostem.

### `tuist_http_connection_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_connection_duration_nanoseconds_bucket-distribution}

Rozkład czasu potrzebnego do nawiązania połączenia z hostem.

### `tuist_http_send_count` (licznik) {#tuist_http_send_count-counter}

Liczba żądań, które zostały wysłane po przypisaniu do połączenia z puli.

### `tuist_http_send_duration_nanoseconds_sum` (sum) {#tuist_http_send_duration_nanoseconds_sum-sum}

Czas potrzebny do wykonania żądań po przypisaniu ich do połączenia z puli.

### `tuist_http_send_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_send_duration_nanoseconds_bucket-distribution}

Rozkład czasu potrzebnego na wykonanie żądań po przypisaniu ich do połączenia z
puli.

### `tuist_http_receive_count` (licznik) {#tuist_http_receive_count-counter}

Liczba odpowiedzi otrzymanych na wysłane zapytania.

### `tuist_http_receive_duration_nanoseconds_sum` (sum) {#tuist_http_receive_duration_nanoseconds_sum-sum}

Czas poświęcony na otrzymanie odpowiedzi.

### `tuist_http_receive_duration_nanoseconds_bucket` (dystrybucja) {#tuist_http_receive_duration_nanoseconds_bucket-distribution}

Rozkład czasu poświęconego na otrzymanie odpowiedzi.

### `tuist_http_queue_available_connections` (last_value) {#tuist_http_queue_available_connections-last_value}

Liczba połączeń dostępnych w kolejce.

### `tuist_http_queue_in_use_connections` (last_value) {#tuist_http_queue_in_use_connections-last_value}

Liczba używanych połączeń w kolejce.
