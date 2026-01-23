---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Instalacja na własnym serwerze {#self-host-installation}

Oferujemy wersję serwera Tuist do samodzielnego hostowania dla organizacji,
które wymagają większej kontroli nad swoją infrastrukturą. Ta wersja pozwala na
hostowanie Tuist na własnej infrastrukturze, zapewniając bezpieczeństwo i
prywatność danych.

::: warning LICENSE REQUIRED
<!-- -->
Samodzielne hostowanie Tuist wymaga ważnej, płatnej licencji. Wersja lokalna
Tuist jest dostępna tylko dla organizacji korzystających z planu Enterprise.
Jeśli jesteś zainteresowany tą wersją, skontaktuj się z
[contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

## Kadencja zwalniania {#release-cadence}

Nowe wersje Tuist są wydawane na bieżąco, w miarę pojawiania się nowych zmian w
wersji głównej. Stosujemy [wersjonowanie semantyczne](https://semver.org/), aby
zapewnić przewidywalność wersjonowania i kompatybilność.

Główny komponent służy do oznaczania istotnych zmian w serwerze Tuist, które
będą wymagały koordynacji z użytkownikami lokalnymi. Nie należy oczekiwać, że
będziemy go używać, a jeśli zajdzie taka potrzeba, zapewniamy, że będziemy
współpracować z Państwem, aby zapewnić płynne przejście.

## Ciągłe wdrażanie {#continuous-deployment}

Zdecydowanie zalecamy skonfigurowanie ciągłego procesu wdrażania, który
codziennie automatycznie wdraża najnowszą wersję Tuist. Dzięki temu zawsze
będziesz mieć dostęp do najnowszych funkcji, ulepszeń i aktualizacji
zabezpieczeń.

Oto przykładowy przepływ pracy GitHub Actions, który codziennie sprawdza i
wdraża nowe wersje:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## Wymagania dotyczące czasu działania {#runtime-requirements}

W tej sekcji opisano wymagania dotyczące hostowania serwera Tuist w
infrastrukturze użytkownika.

### Matryca zgodności {#compatibility-matrix}

Serwer Tuist został przetestowany i jest kompatybilny z następującymi
minimalnymi wersjami:

| Komponent   | Minimalna wersja | Uwagi                                           |
| ----------- | ---------------- | ----------------------------------------------- |
| PostgreSQL  | 15               | Z rozszerzeniem TimescaleDB                     |
| TimescaleDB | 2.16.1           | Wymagane rozszerzenie PostgreSQL (przestarzałe) |
| ClickHouse  | 25               | Wymagane do celów analitycznych                 |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB jest obecnie wymaganym rozszerzeniem PostgreSQL dla serwera Tuist,
używanym do przechowywania i wyszukiwania danych szeregów czasowych. Jednak
**TimescaleDB jest przestarzałe** i zostanie usunięte jako wymagana zależność w
najbliższej przyszłości, ponieważ przenosimy wszystkie funkcje szeregów
czasowych do ClickHouse. Na razie upewnij się, że Twoja instancja PostgreSQL ma
zainstalowane i włączone TimescaleDB.
<!-- -->
:::

### Uruchamianie zwirtualizowanych obrazów Docker {#running-dockervirtualized-images}

Serwer dystrybuujemy jako obraz [Docker](https://www.docker.com/) za
pośrednictwem [rejestru kontenerów
GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Aby uruchomić program, Twoja infrastruktura musi obsługiwać obrazy Docker.
Należy pamiętać, że większość dostawców infrastruktury obsługuje tę technologię,
ponieważ stała się ona standardowym kontenerem do dystrybucji i uruchamiania
oprogramowania w środowiskach produkcyjnych.

### Baza danych Postgres {#postgres-database}

Oprócz uruchomienia obrazów Docker, potrzebna będzie baza danych Postgres z
rozszerzeniem TimescaleDB do przechowywania danych relacyjnych i szeregów
czasowych. Większość dostawców infrastruktury oferuje bazy danych Postgres (np.
AWS i Google Cloud).

**Wymagane rozszerzenie TimescaleDB:** Tuist wymaga rozszerzenia TimescaleDB do
wydajnego przechowywania i wyszukiwania danych szeregów czasowych. Rozszerzenie
to jest używane do zdarzeń poleceń, analiz i innych funkcji opartych na czasie.
Przed uruchomieniem Tuist upewnij się, że instancja PostgreSQL ma zainstalowane
i włączone rozszerzenie TimescaleDB.

::: info MIGRATIONS
<!-- -->
Punkt wejścia obrazu Docker automatycznie uruchamia wszelkie oczekujące migracje
schematu przed uruchomieniem usługi. Jeśli migracje zakończą się niepowodzeniem
z powodu brakującego rozszerzenia TimescaleDB, należy najpierw zainstalować je w
bazie danych.
<!-- -->
:::

### Baza danych ClickHouse {#clickhouse-database}

**Tuist wykorzystuje [ClickHouse](https://clickhouse.com/) do przechowywania i
wyszukiwania dużych ilości danych analitycznych. ClickHouse jest wymagany** do
funkcji takich jak budowanie wniosków i będzie główną bazą danych szeregów
czasowych, gdy wycofamy TimescaleDB. Możesz wybrać, czy chcesz samodzielnie
hostować ClickHouse, czy korzystać z ich usługi hostowanej.

::: info MIGRATIONS
<!-- -->
Punkt wejścia obrazu Docker automatycznie uruchamia wszelkie oczekujące migracje
schematu ClickHouse przed uruchomieniem usługi.
<!-- -->
:::

### Przechowywanie {#storage}

Potrzebne będzie również rozwiązanie do przechowywania plików (np. plików
binarnych frameworków i bibliotek). Obecnie obsługujemy wszystkie pamięci masowe
zgodne ze standardem S3.

::: tip OPTIMIZED CACHING
<!-- -->
Jeśli Twoim głównym celem jest posiadanie własnego zasobnika do przechowywania
plików binarnych i zmniejszenie opóźnień pamięci podręcznej, być może nie musisz
samodzielnie hostować całego serwera. Możesz samodzielnie hostować węzły pamięci
podręcznej i podłączyć je do hostowanego serwera Tuist lub do swojego własnego
serwera.

Zobacz <LocalizedLink href="/guides/cache/self-host">przewodnik dotyczący
samodzielnego hostowania pamięci podręcznej</LocalizedLink>.
<!-- -->
:::

## Konfiguracja {#configuration}

Konfiguracja usługi odbywa się w czasie wykonywania poprzez zmienne
środowiskowe. Ze względu na wrażliwy charakter tych zmiennych zalecamy ich
szyfrowanie i przechowywanie w bezpiecznych rozwiązaniach do zarządzania
hasłami. Możesz mieć pewność, że Tuist traktuje te zmienne z najwyższą
ostrożnością, zapewniając, że nigdy nie zostaną one wyświetlone w logach.

::: info LAUNCH CHECKS
<!-- -->
Niezbędne zmienne są weryfikowane podczas uruchamiania. Jeśli jakiejś brakuje,
uruchomienie nie powiedzie się, a komunikat o błędzie będzie zawierał
szczegółowe informacje o brakujących zmiennych.
<!-- -->
:::

### Konfiguracja licencji {#license-configuration}

Jako użytkownik lokalny otrzymasz klucz licencyjny, który należy udostępnić jako
zmienną środowiskową. Klucz ten służy do weryfikacji licencji i zapewnienia, że
usługa działa zgodnie z warunkami umowy.

| Zmienna środowiskowa               | Opis                                                                                                                                                                                                                                                                         | Wymagane | Domyślne | Przykłady                                 |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------- | ----------------------------------------- |
| `TUIST_LICENSE`                    | Licencja udzielona po podpisaniu umowy o gwarantowanym poziomie usług                                                                                                                                                                                                        | Tak*     |          | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **Wyjątkowa alternatywa dla `TUIST_LICENSE`**. Certyfikat publiczny zakodowany w Base64 do offline'owej walidacji licencji w środowiskach izolowanych, gdzie serwer nie może łączyć się z usługami zewnętrznymi. Używaj tylko wtedy, gdy `TUIST_LICENSE` nie może być użyte. | Tak*     |          | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* Należy podać albo `TUIST_LICENSE`, albo `TUIST_LICENSE_CERTIFICATE_BASE64`,
ale nie oba. W przypadku standardowych wdrożeń należy użyć `TUIST_LICENSE`.

::: warning EXPIRATION DATE
<!-- -->
Licencje mają datę ważności. Użytkownicy otrzymają ostrzeżenie podczas
korzystania z poleceń Tuist, które współdziałają z serwerem, jeśli licencja
wygaśnie w ciągu mniej niż 30 dni. Jeśli jesteś zainteresowany odnowieniem
licencji, skontaktuj się z [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

### Konfiguracja środowiska podstawowego {#base-environment-configuration}

| Zmienna środowiskowa                  | Opis                                                                                                                                                                                                                                    | Wymagane | Domyślne                           | Przykłady                                                                       |                                                                                                                                    |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | Podstawowy adres URL umożliwiający dostęp do instancji z Internetu                                                                                                                                                                      | Tak      |                                    | https://tuist.dev                                                               |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | Klucz używany do szyfrowania informacji (np. sesji w pliku cookie)                                                                                                                                                                      | Tak      |                                    |                                                                                 | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper do generowania haseł z hashami                                                                                                                                                                                                   | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Tajny klucz do generowania losowych tokenów                                                                                                                                                                                             | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 32-bajtowy klucz do szyfrowania danych wrażliwych za pomocą algorytmu AES-GCM                                                                                                                                                           | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | Kiedy `1`, aplikacja zostaje skonfigurowana do korzystania z adresów IPv6.                                                                                                                                                              | Nie      | `0`                                | `1`                                                                             |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | Poziom logowania używany dla aplikacji                                                                                                                                                                                                  | Nie      | `info`                             | [Poziomy logowania](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | Wersja URL nazwy Twojej aplikacji GitHub                                                                                                                                                                                                | Nie      |                                    | `my-app`                                                                        |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | Klucz prywatny zakodowany w base64 używany w aplikacji GitHub do odblokowania dodatkowych funkcji, takich jak automatyczne publikowanie komentarzy PR.                                                                                  | Nie      | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                                 |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | Klucz prywatny używany przez aplikację GitHub do odblokowania dodatkowych funkcji, takich jak automatyczne publikowanie komentarzy PR. **Zalecamy używanie wersji zakodowanej w base64, aby uniknąć problemów ze znakami specjalnymi.** | Nie      | `-----BEGIN RSA...`                |                                                                                 |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | Rozdzielona przecinkami lista nazw użytkowników, którzy mają dostęp do adresów URL operacji.                                                                                                                                            | Nie      |                                    | `user1,user2`                                                                   |                                                                                                                                    |
| `TUIST_WEB`                           | Włącz punkt końcowy serwera WWW.                                                                                                                                                                                                        | Nie      | `1`                                | `1` lub `0`                                                                     |                                                                                                                                    |

### Konfiguracja bazy danych {#database-configuration}

Do konfiguracji połączenia z bazą danych używane są następujące zmienne
środowiskowe:

| Zmienna środowiskowa                 | Opis                                                                                                                                                                                                                            | Wymagane | Domyślne  | Przykłady                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Adres URL umożliwiający dostęp do bazy danych Postgres. Należy pamiętać, że adres URL powinien zawierać informacje uwierzytelniające.                                                                                           | Tak      |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | Adres URL umożliwiający dostęp do bazy danych ClickHouse. Należy pamiętać, że adres URL powinien zawierać informacje uwierzytelniające.                                                                                         | Nie      |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | Jeśli wartość jest prawdziwa, używa [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) do połączenia z bazą danych.                                                                                                  | Nie      | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | Liczba połączeń, które mają pozostać otwarte w puli połączeń                                                                                                                                                                    | Nie      | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | Interwał (w milisekundach) sprawdzania, czy wszystkie połączenia pobrane z puli zajęły więcej czasu niż interwał kolejki [(Więcej informacji)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)    | Nie      | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | Czas progowy (w milisekundach) w kolejce, który pula wykorzystuje do określenia, czy należy zacząć odrzucać nowe połączenia [(Więcej informacji)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Nie      | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | Odstęp czasu w milisekundach między opróżnianiem bufora ClickHouse                                                                                                                                                              | Nie      | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | Maksymalny rozmiar bufora ClickHouse w bajtach przed wymuszeniem opróżnienia                                                                                                                                                    | Nie      | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | Liczba procesów buforowych ClickHouse do uruchomienia                                                                                                                                                                           | Nie      | `5`       | `5`                                                                    |

### Konfiguracja środowiska uwierzytelniania {#authentication-environment-configuration}

Ułatwiamy uwierzytelnianie poprzez [dostawców tożsamości
(IdP)](https://en.wikipedia.org/wiki/Identity_provider). Aby z tego skorzystać,
upewnij się, że wszystkie niezbędne zmienne środowiskowe dla wybranego dostawcy
są obecne w środowisku serwera. **Brakujące zmienne** spowodują, że Tuist ominie
tego dostawcę.

#### GitHub {#github}

Zalecamy uwierzytelnianie za pomocą aplikacji [GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps),
ale można również użyć aplikacji [OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app).
Upewnij się, że w środowisku serwera znajdują się wszystkie niezbędne zmienne
środowiskowe określone przez GitHub. Brak zmiennych spowoduje, że Tuist pominie
uwierzytelnianie GitHub. Aby poprawnie skonfigurować aplikację GitHub:
- W ogólnych ustawieniach aplikacji GitHub:
    - Skopiuj identyfikator klienta `` i ustaw go jako
      `TUIST_GITHUB_APP_CLIENT_ID`
    - Utwórz i skopiuj nowy sekret klienta `` i ustaw go jako
      `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Ustaw adres URL wywołania zwrotnego `` jako
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` może być
      również adresem IP Twojego serwera.
- Wymagane są następujące uprawnienia:
  - Repozytoria:
    - Pull requesty: czytanie i pisanie
  - Konta:
    - Adresy e-mail: tylko do odczytu

`W sekcji „Uprawnienia i zdarzenia”` „ `” „Uprawnienia konta”` „ `” „Adresy
e-mail”` „ `” „Tylko do odczytu”`.

Następnie należy udostępnić następujące zmienne środowiskowe w środowisku, w
którym działa serwer Tuist:

| Zmienna środowiskowa             | Opis                                   | Wymagane | Domyślne | Przykłady                                  |
| -------------------------------- | -------------------------------------- | -------- | -------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | Identyfikator klienta aplikacji GitHub | Tak      |          | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Sekret klienta aplikacji               | Tak      |          | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

Możesz skonfigurować uwierzytelnianie za pomocą Google, korzystając z [OAuth
2](https://developers.google.com/identity/protocols/oauth2). W tym celu musisz
utworzyć nowe poświadczenie typu OAuth client ID. Podczas tworzenia poświadczeń
wybierz „Web Application” jako typ aplikacji, nazwij ją `Tuist` i ustaw adres
URI przekierowania na `{base_url}/users/auth/google/callback`, gdzie `base_url`
jest adresem URL, pod którym działa Twoja usługa hostowana. Po utworzeniu
aplikacji skopiuj identyfikator klienta i sekret, a następnie ustaw je jako
zmienne środowiskowe odpowiednio `GOOGLE_CLIENT_ID` i `GOOGLE_CLIENT_SECRET`.

::: info CONSENT SCREEN SCOPES
<!-- -->
Być może konieczne będzie utworzenie ekranu zgody. W takim przypadku należy
dodać zakresy `userinfo.email` i `openid` oraz oznaczyć aplikację jako
wewnętrzną.
<!-- -->
:::

#### Okta {#okta}

Możesz włączyć uwierzytelnianie za pomocą Okta poprzez protokół [OAuth
2.0](https://oauth.net/2/). Musisz [utworzyć
aplikację](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
w Okta, postępując zgodnie z
<LocalizedLink href="/guides/integrations/sso#okta">tymi
instrukcjami</LocalizedLink>.

Po uzyskaniu identyfikatora klienta i klucza tajnego podczas konfiguracji
aplikacji Okta należy ustawić następujące zmienne środowiskowe:

| Zmienna środowiskowa         | Opis                                                                                                     | Wymagane | Domyślne | Przykłady |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- | -------- | -------- | --------- |
| `TUIST_OKTA_1_CLIENT_ID`     | Identyfikator klienta do uwierzytelniania w Okta. Numer powinien być identyfikatorem Twojej organizacji. | Tak      |          |           |
| `TUIST_OKTA_1_CLIENT_SECRET` | Sekret klienta do uwierzytelniania w Okta                                                                | Tak      |          |           |

Numer `1` należy zastąpić identyfikatorem organizacji. Zazwyczaj jest to 1, ale
należy to sprawdzić w bazie danych.

### Konfiguracja środowiska pamięci masowej {#storage-environment-configuration}

**Tuist potrzebuje pamięci masowej do przechowywania artefaktów przesłanych za
pośrednictwem API. Aby Tuist działał efektywnie, konieczne jest skonfigurowanie
jednego z obsługiwanych rozwiązań pamięci masowej**.

#### Magazyny zgodne z S3 {#s3compliant-storages}

Do przechowywania artefaktów można używać dowolnego dostawcy pamięci masowej
zgodnego z S3. Do uwierzytelnienia i skonfigurowania integracji z dostawcą
pamięci masowej wymagane są następujące zmienne środowiskowe:

| Zmienna środowiskowa                                     | Opis                                                                                                                                                                                      | Wymagane | Domyślne                         | Przykłady                                                     |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` lub `AWS_ACCESS_KEY_ID`         | Identyfikator klucza dostępu do uwierzytelniania w dostawcy pamięci masowej                                                                                                               | Tak      |                                  | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` lub `AWS_SECRET_ACCESS_KEY` | Sekretny klucz dostępu do uwierzytelniania w usłudze przechowywania danych                                                                                                                | Tak      |                                  | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` lub `AWS_REGION`                       | Region, w którym znajduje się wiadro                                                                                                                                                      | Nie      | `auto`                           | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` lub `AWS_ENDPOINT`                   | Punkt końcowy dostawcy pamięci masowej                                                                                                                                                    | Tak      |                                  | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                   | Nazwa zasobnika, w którym będą przechowywane artefakty.                                                                                                                                   | Tak      |                                  | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                   | Certyfikat CA zakodowany w formacie PEM do weryfikacji połączeń HTTPS S3. Przydatny w środowiskach izolowanych z certyfikatami z podpisem własnym lub wewnętrznymi urzędami certyfikacji. | Nie      | Pakiet systemowy CA              | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                               | Limit czasu (w milisekundach) na nawiązanie połączenia z dostawcą pamięci masowej.                                                                                                        | Nie      | `3000`                           | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                               | Limit czasu (w milisekundach) na odbiór danych od dostawcy pamięci masowej.                                                                                                               | Nie      | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                  | Limit czasu (w milisekundach) dla puli połączeń z dostawcą pamięci masowej. Użyj `infinity`, aby wyłączyć limit czasu.                                                                    | Nie      | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                            | Maksymalny czas bezczynności (w milisekundach) dla połączeń w puli. Użyj `infinity`, aby połączenia pozostawały aktywne przez czas nieograniczony.                                        | Nie      | `nieskończoność`                 | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                     | Maksymalna liczba połączeń na pulę                                                                                                                                                        | Nie      | `500`                            | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                    | Liczba pul połączeń do wykorzystania                                                                                                                                                      | Nie      | Liczba harmonogramów systemowych | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                      | Protokół używany podczas łączenia się z dostawcą pamięci masowej (`http1` lub `http2`)                                                                                                    | Nie      | `http1`                          | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                  | Czy adres URL powinien być skonstruowany z nazwą bucket jako subdomeną (wirtualnym hostem)?                                                                                               | Nie      | `false`                          | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
Jeśli Twoim dostawcą pamięci masowej jest AWS i chcesz uwierzytelnić się za
pomocą tokenu tożsamości internetowej, możesz ustawić zmienną środowiskową
`TUIST_S3_AUTHENTICATION_METHOD` na `aws_web_identity_token_from_env_vars`, a
Tuist użyje tej metody przy użyciu konwencjonalnych zmiennych środowiskowych
AWS.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
W przypadku Google Cloud Storage postępuj zgodnie z [tymi
dokumentami](https://cloud.google.com/storage/docs/authentication/managing-hmackeys),
aby uzyskać parę `AWS_ACCESS_KEY_ID` i `AWS_SECRET_ACCESS_KEY`. `AWS_ENDPOINT`
należy ustawić na `https://storage.googleapis.com`. Pozostałe zmienne
środowiskowe są takie same jak w przypadku każdej innej pamięci zgodnej z S3.

### Konfiguracja poczty e-mail {#email-configuration}

Tuist wymaga funkcji poczty elektronicznej do uwierzytelniania użytkowników i
powiadomień transakcyjnych (np. resetowanie hasła, powiadomienia dotyczące
konta). Obecnie **obsługuje wyłącznie Mailgun** jako dostawcę poczty
elektronicznej.

| Zmienna środowiskowa             | Opis                                                                                                                                                                                     | Wymagane | Domyślne                                                                                                              | Przykłady                   |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Klucz API do uwierzytelniania w Mailgun                                                                                                                                                  | Tak*     |                                                                                                                       | `key-1234567890abcdef`      |
| `TUIST_MAILING_DOMAIN`           | Domena, z której będą wysyłane wiadomości e-mail                                                                                                                                         | Tak*     |                                                                                                                       | `mg.tuist.io`               |
| `TUIST_MAILING_FROM_ADDRESS`     | Adres e-mail, który pojawi się w polu „Od”.                                                                                                                                              | Tak*     |                                                                                                                       | `noreply@tuist.io`          |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Opcjonalny adres zwrotny dla odpowiedzi użytkowników                                                                                                                                     | Nie      |                                                                                                                       | `support@tuist.dev`         |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | Pomiń potwierdzenie adresu e-mail dla nowych rejestracji użytkowników. Po włączeniu tej opcji użytkownicy są automatycznie potwierdzani i mogą zalogować się natychmiast po rejestracji. | Nie      | `prawda`, jeśli poczta elektroniczna nie jest skonfigurowana, `fałsz`, jeśli poczta elektroniczna jest skonfigurowana | `prawda`, `fałsz`, `1`, `0` |

\* Zmienne konfiguracyjne poczty e-mail są wymagane tylko wtedy, gdy chcesz
wysyłać wiadomości e-mail. Jeśli nie są skonfigurowane, potwierdzenie e-mailowe
jest automatycznie pomijane.

::: info SMTP SUPPORT
<!-- -->
Obecnie nie jest dostępna ogólna obsługa protokołu SMTP. Jeśli potrzebujesz
obsługi protokołu SMTP dla wdrożenia lokalnego, skontaktuj się z
[contact@tuist.dev](mailto:contact@tuist.dev), aby omówić swoje wymagania.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
W przypadku instalacji lokalnych bez dostępu do Internetu lub konfiguracji
dostawcy poczty e-mail potwierdzenie e-mailowe jest domyślnie pomijane.
Użytkownicy mogą zalogować się natychmiast po rejestracji. Jeśli masz
skonfigurowaną pocztę e-mail, ale nadal chcesz pominąć potwierdzenie, ustaw
`TUIST_SKIP_EMAIL_CONFIRMATION=true`. Aby wymagać potwierdzenia e-mailowego po
skonfigurowaniu poczty e-mail, ustaw `TUIST_SKIP_EMAIL_CONFIRMATION=false`.
<!-- -->
:::

### Konfiguracja platformy Git {#git-platform-configuration}

Tuist może <LocalizedLink href="/guides/server/authentication">zintegrować się z
platformami Git</LocalizedLink>, aby zapewnić dodatkowe funkcje, takie jak
automatyczne publikowanie komentarzy w pull requestach.

#### GitHub {#platform-github}

Musisz [utworzyć aplikację
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
Możesz ponownie użyć aplikacji utworzonej do uwierzytelniania, chyba że
utworzyłeś aplikację OAuth GitHub. W sekcji `Uprawnienia i zdarzenia`'s
`Uprawnienia repozytorium` musisz dodatkowo ustawić `Pull requests` uprawnienie
`Odczyt i zapis`.

Oprócz `TUIST_GITHUB_APP_CLIENT_ID` i `TUIST_GITHUB_APP_CLIENT_SECRET` potrzebne
będą następujące zmienne środowiskowe:

| Zmienna środowiskowa           | Opis                            | Wymagane | Domyślne | Przykłady                            |
| ------------------------------ | ------------------------------- | -------- | -------- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | Klucz prywatny aplikacji GitHub | Tak      |          | `-----BEGIN RSA PRIVATE KEY-----...` |

## Lokalne testy {#testing-locally}

Zapewniamy kompleksową konfigurację Docker Compose, która zawiera wszystkie
wymagane zależności do przetestowania serwera Tuist na komputerze lokalnym przed
wdrożeniem w infrastrukturze:

- PostgreSQL 15 z rozszerzeniem TimescaleDB 2.16 (przestarzałe)
- ClickHouse 25 do analizy danych
- ClickHouse Keeper do koordynacji
- MinIO dla pamięci masowej zgodnej z S3
- Redis do trwałego przechowywania KV w różnych wdrożeniach (opcjonalnie)
- pgweb do administrowania bazami danych

::: danger LICENSE REQUIRED
<!-- -->
Aby uruchomić serwer Tuist, w tym lokalne instancje programistyczne, wymagana
jest prawidłowa zmienna środowiskowa `TUIST_LICENSE`. Jeśli potrzebujesz
licencji, skontaktuj się z [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

**Szybki start:**

1. Pobierz pliki konfiguracyjne:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. Skonfiguruj zmienne środowiskowe:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. Uruchom wszystkie usługi:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. Wejdź na serwer pod adresem http://localhost:8080

**Punkty końcowe usługi:**
- Serwer Tuist: http://localhost:8080
- Konsola MinIO: http://localhost:9003 (dane uwierzytelniające: `tuist` /
  `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Typowe polecenia:**

Sprawdź status usługi:
```bash
docker compose ps
# or: podman compose ps
```

Wyświetl logi:
```bash
docker compose logs -f tuist
```

Zatrzymaj usługi:
```bash
docker compose down
```

Zresetuj wszystko (usuwa wszystkie dane):
```bash
docker compose down -v
```

**Pliki konfiguracyjne:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Kompletna
  konfiguracja Docker Compose
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) -
  Konfiguracja ClickHouse
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - Konfiguracja ClickHouse Keeper
- [.env.example](/server/self-host/.env.example) - Przykładowy plik zmiennych
  środowiskowych

## Wdrożenie {#deployment}

Oficjalny obraz Tuist Docker jest dostępny pod adresem:
```
ghcr.io/tuist/tuist
```

### Pobieranie obrazu Docker {#pulling-the-docker-image}

Możesz pobrać obraz, wykonując następujące polecenie:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Lub pobierz konkretną wersję:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Wdrażanie obrazu Docker {#deploying-the-docker-image}

Proces wdrażania obrazu Docker będzie się różnił w zależności od wybranego
dostawcy usług w chmurze i podejścia Twojej organizacji do ciągłego wdrażania.
Ponieważ większość rozwiązań i narzędzi chmurowych, takich jak
[Kubernetes](https://kubernetes.io/), wykorzystuje obrazy Docker jako podstawowe
jednostki, przykłady w tej sekcji powinny dobrze pasować do Twojej obecnej
konfiguracji.

::: warning
<!-- -->
Jeśli potok wdrażania wymaga sprawdzenia, czy serwer działa, możesz wysłać
żądanie HTTP GET `` do `/ready` i sprawdzić, czy w odpowiedzi znajduje się kod
statusu `200`.
<!-- -->
:::

#### Latać {#fly}

Aby wdrożyć aplikację na [Fly](https://fly.io/), potrzebny będzie plik
konfiguracyjny `fly.toml`. Rozważ wygenerowanie go dynamicznie w ramach procesu
ciągłego wdrażania (CD). Poniżej znajduje się przykładowy plik, który można
wykorzystać:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Następnie możesz uruchomić `fly launch --local-only --no-deploy`, aby uruchomić
aplikację. Przy kolejnych wdrożeniach, zamiast uruchamiać `fly launch
--local-only`, należy uruchomić `fly deploy --local-only`. Fly.io nie pozwala na
pobieranie prywatnych obrazów Docker, dlatego musimy użyć flagi `--local-only`.


## Metryki Prometeusza {#prometheus-metrics}

Tuist udostępnia metryki Prometheus pod adresem `/metrics`, aby pomóc Ci
monitorować Twoją własną instancję. Metryki te obejmują:

### Metryki klienta HTTP Finch {#finch-metrics}

Tuist używa [Finch](https://github.com/sneako/finch) jako swojego klienta HTTP i
udostępnia szczegółowe dane dotyczące żądań HTTP:

#### Wymagane metryki
- `tuist_prom_ex_finch_request_count_total` - Łączna liczba żądań Finch
  (licznik)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Czas trwania żądań HTTP
  (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Przedziały czasowe: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 s, 2,5 s, 5 s,
    10 s
- `tuist_prom_ex_finch_request_exception_count_total` - Łączna liczba wyjątków
  dotyczących żądań Finch (licznik)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### Metryki kolejki puli połączeń
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Czas oczekiwania w kolejce
  puli połączeń (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Przedziały czasowe: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms,
    1 s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Czas, przez jaki
  połączenie pozostawało bezczynne przed użyciem (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Przedziały czasowe: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 s, 5 s, 10 s
- `tuist_prom_ex_finch_queue_exception_count_total` - Łączna liczba wyjątków
  kolejki Finch (licznik)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Metryki połączeń
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Czas potrzebny do
  nawiązania połączenia (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `error`
  - Przedziały czasowe: 10 ms, 50 ms, 100 ms, 250 ms, 500 ms, 1 s, 2,5 s, 5 s
- `tuist_prom_ex_finch_connect_count_total` - Łączna liczba prób połączenia
  (licznik)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`

#### Wyślij dane
- `tuist_prom_ex_finch_send_duration_milliseconds` - Czas wysyłania żądania
  (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Przedziały czasowe: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms,
    1 s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Czas bezczynności
  połączenia przed wysłaniem (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Przedziały czasowe: 1 ms, 5 ms, 10 ms, 25 ms, 50 ms, 100 ms, 250 ms, 500 ms

Wszystkie metryki histogramu zapewniają warianty `_bucket`, `_sum` oraz `_count`
do szczegółowej analizy.

### Inne wskaźniki

Oprócz wskaźników Finch, Tuist udostępnia wskaźniki dla:
- Wydajność maszyny wirtualnej BEAM
- Niestandardowe wskaźniki logiki biznesowej (pamięć, konta, projekty itp.)
- Wydajność bazy danych (w przypadku korzystania z infrastruktury hostowanej
  przez Tuist)

## Operacje {#operations}

Tuist udostępnia zestaw narzędzi pod adresem `/ops/`, które można wykorzystać do
zarządzania instancją.

::: warning Authorization
<!-- -->
Dostęp do punktów końcowych `/ops/` mają wyłącznie osoby, których nazwy
użytkownika są wymienione w zmiennej środowiskowej `TUIST_OPS_USER_HANDLES`.
<!-- -->
:::

- **Błędy (`/ops/errors`):** Możesz wyświetlić nieoczekiwane błędy, które
  wystąpiły w aplikacji. Jest to przydatne do debugowania i zrozumienia, co
  poszło nie tak. Możemy poprosić Cię o udostępnienie nam tych informacji, jeśli
  napotkasz problemy.
- **Pulpit nawigacyjny (`/ops/dashboard`):** Możesz wyświetlić pulpit
  nawigacyjny, który zawiera informacje na temat wydajności i stanu aplikacji
  (np. zużycie pamięci, uruchomione procesy, liczba żądań). Pulpit nawigacyjny
  może być bardzo przydatny do oceny, czy używany sprzęt jest wystarczający do
  obsługi obciążenia.
