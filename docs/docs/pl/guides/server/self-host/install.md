---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Instalacja na własnym hostingu {#self-host-installation}

Oferujemy samodzielnie hostowaną wersję serwera Tuist dla organizacji, które
wymagają większej kontroli nad swoją infrastrukturą. Ta wersja umożliwia
hostowanie Tuist na własnej infrastrukturze, zapewniając bezpieczeństwo i
prywatność danych.

::: warning LICENSE REQUIRED
<!-- -->
Samodzielny hosting Tuist wymaga prawnie ważnej płatnej licencji. Lokalna wersja
Tuist jest dostępna tylko dla organizacji korzystających z planu Enterprise.
Jeśli jesteś zainteresowany tą wersją, skontaktuj się z
[contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

## Kadencja zwalniania {#release-cadence}

Wydajemy nowe wersje Tuist w sposób ciągły, w miarę jak nowe możliwe do wydania
zmiany trafiają na main. Stosujemy [semantic versioning](https://semver.org/),
aby zapewnić przewidywalne wersjonowanie i kompatybilność.

Główny komponent służy do oznaczania przełomowych zmian na serwerze Tuist, które
będą wymagały koordynacji z użytkownikami on-premise. Nie powinieneś oczekiwać,
że będziemy go używać, a jeśli zajdzie taka potrzeba, zapewniamy, że będziemy
współpracować z Tobą, aby przejście było płynne.

## Ciągłe wdrażanie {#continuous-deployment}

Zdecydowanie zalecamy skonfigurowanie potoku ciągłego wdrażania, który
automatycznie wdraża najnowszą wersję Tuist każdego dnia. Dzięki temu zawsze
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

W tej sekcji przedstawiono wymagania dotyczące hostowania serwera Tuist w
infrastrukturze użytkownika.

### Matryca zgodności {#compatibility-matrix}

Serwer Tuist został przetestowany i jest kompatybilny z następującymi
minimalnymi wersjami:

| Komponent   | Wersja minimalna | Uwagi                                           |
| ----------- | ---------------- | ----------------------------------------------- |
| PostgreSQL  | 15               | Z rozszerzeniem TimescaleDB                     |
| TimescaleDB | 2.16.1           | Wymagane rozszerzenie PostgreSQL (przestarzałe) |
| ClickHouse  | 25               | Wymagane do analizy                             |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB jest obecnie wymaganym rozszerzeniem PostgreSQL dla serwera Tuist,
używanym do przechowywania danych szeregów czasowych i wysyłania zapytań.
Jednakże, **TimescaleDB jest przestarzałe** i zostanie usunięte jako wymagana
zależność w najbliższej przyszłości, ponieważ migrujemy całą funkcjonalność
szeregów czasowych do ClickHouse. Na razie upewnij się, że twoja instancja
PostgreSQL ma zainstalowaną i włączoną usługę TimescaleDB.
<!-- -->
:::

### Uruchamianie zwirtualizowanych obrazów Docker {#running-dockervirtualized-images}

Dystrybuujemy serwer jako obraz [Docker](https://www.docker.com/) za
pośrednictwem [GitHub's Container
Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Aby go uruchomić, infrastruktura musi obsługiwać uruchamianie obrazów Docker.
Należy pamiętać, że większość dostawców infrastruktury obsługuje tę technologię,
ponieważ stała się ona standardowym kontenerem do dystrybucji i uruchamiania
oprogramowania w środowiskach produkcyjnych.

### Baza danych Postgres {#postgres-database}

Oprócz uruchomienia obrazów Docker, do przechowywania danych relacyjnych i
szeregów czasowych potrzebna będzie baza danych
[Postgres](https://www.postgresql.org/) z rozszerzeniem
[TimescaleDB](https://www.timescale.com/). Większość dostawców infrastruktury
posiada w swojej ofercie bazy danych Postgres (np.
[AWS](https://aws.amazon.com/rds/postgresql/) i [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**Wymagane rozszerzenie TimescaleDB:** Tuist wymaga rozszerzenia TimescaleDB do
wydajnego przechowywania danych szeregów czasowych i wysyłania zapytań.
Rozszerzenie to jest używane do obsługi zdarzeń, analiz i innych funkcji
opartych na czasie. Upewnij się, że twoja instancja PostgreSQL ma zainstalowane
i włączone TimescaleDB przed uruchomieniem Tuist.

::: info MIGRATIONS
<!-- -->
Punkt wejścia obrazu Docker automatycznie uruchamia wszelkie oczekujące migracje
schematów przed uruchomieniem usługi. Jeśli migracje nie powiodą się z powodu
braku rozszerzenia TimescaleDB, należy najpierw zainstalować je w bazie danych.
<!-- -->
:::

### Baza danych ClickHouse {#clickhouse-database}

Tuist używa [ClickHouse](https://clickhouse.com/) do przechowywania i
wyszukiwania dużych ilości danych analitycznych. ClickHouse jest **wymagany**
dla funkcji takich jak build insights i będzie podstawową bazą danych szeregów
czasowych w miarę wycofywania TimescaleDB. Możesz wybrać, czy chcesz
samodzielnie hostować ClickHouse, czy skorzystać z ich hostowanej usługi.

::: info MIGRATIONS
<!-- -->
Punkt wejścia obrazu Docker automatycznie uruchamia wszelkie oczekujące migracje
schematów ClickHouse przed uruchomieniem usługi.
<!-- -->
:::

### Przechowywanie {#storage}

Potrzebne będzie również rozwiązanie do przechowywania plików (np. plików
binarnych frameworków i bibliotek). Obecnie obsługujemy dowolną pamięć masową
zgodną ze standardem S3.

## Konfiguracja {#configuration}

Konfiguracja usługi odbywa się w czasie wykonywania poprzez zmienne
środowiskowe. Biorąc pod uwagę wrażliwy charakter tych zmiennych, zalecamy ich
szyfrowanie i przechowywanie w bezpiecznych rozwiązaniach do zarządzania
hasłami. Zapewniamy, że Tuist obsługuje te zmienne z najwyższą starannością,
zapewniając, że nigdy nie są one wyświetlane w dziennikach.

::: info LAUNCH CHECKS
<!-- -->
Niezbędne zmienne są weryfikowane podczas uruchamiania. Jeśli jakiejkolwiek
brakuje, uruchomienie nie powiedzie się, a komunikat o błędzie wyszczególni
brakujące zmienne.
<!-- -->
:::

### Konfiguracja licencji {#license-configuration}

Jako użytkownik lokalny otrzymasz klucz licencyjny, który musisz ujawnić jako
zmienną środowiskową. Klucz ten służy do walidacji licencji i zapewnienia, że
usługa działa zgodnie z warunkami umowy.

| Zmienna środowiskowa               | Opis                                                                                                                                                                                                                                                                 | Wymagane | Domyślne | Przykłady                                 |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------- | ----------------------------------------- |
| `TUIST_LICENSE`                    | Licencja udzielana po podpisaniu umowy o gwarantowanym poziomie usług                                                                                                                                                                                                | Tak*     |          | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **Wyjątkowa alternatywa dla `TUIST_LICENSE`**. Certyfikat publiczny zakodowany w Base64 do walidacji licencji offline w środowiskach, w których serwer nie może skontaktować się z usługami zewnętrznymi. Używaj tylko wtedy, gdy `TUIST_LICENSE` nie może być użyty | Tak*     |          | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* Należy podać albo `TUIST_LICENSE` albo `TUIST_LICENSE_CERTIFICATE_BASE64`,
ale nie oba. W przypadku standardowych wdrożeń należy użyć `TUIST_LICENSE`.

::: warning EXPIRATION DATE
<!-- -->
Licencje mają datę wygaśnięcia. Użytkownicy otrzymają ostrzeżenie podczas
korzystania z poleceń Tuist, które wchodzą w interakcję z serwerem, jeśli
licencja wygaśnie za mniej niż 30 dni. Jeśli jesteś zainteresowany odnowieniem
licencji, skontaktuj się z [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

### Konfiguracja środowiska podstawowego {#base-environment-configuration}

| Zmienna środowiskowa                  | Opis                                                                                                                                                                                                                                  | Wymagane | Domyślne                           | Przykłady                                                                       |                                                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | Podstawowy adres URL umożliwiający dostęp do instancji z Internetu                                                                                                                                                                    | Tak      |                                    | https://tuist.dev                                                               |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | Klucz używany do szyfrowania informacji (np. sesji w pliku cookie).                                                                                                                                                                   | Tak      |                                    |                                                                                 | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper do generowania hashowanych haseł                                                                                                                                                                                               | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | Tajny klucz do generowania losowych tokenów                                                                                                                                                                                           | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 32-bajtowy klucz do szyfrowania poufnych danych AES-GCM                                                                                                                                                                               | Nie      | `$TUIST_SECRET_KEY_BASE`           |                                                                                 |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | Gdy `1` konfiguruje aplikację do korzystania z adresów IPv6                                                                                                                                                                           | Nie      | `0`                                | `1`                                                                             |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | Poziom dziennika używany przez aplikację                                                                                                                                                                                              | Nie      | `info`                             | [Poziomy dziennika](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | Wersja adresu URL nazwy aplikacji GitHub                                                                                                                                                                                              | Nie      |                                    | `my-app`                                                                        |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | Zakodowany w base64 klucz prywatny używany w aplikacji GitHub do odblokowywania dodatkowych funkcji, takich jak publikowanie automatycznych komentarzy PR.                                                                            | Nie      | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                                 |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | Klucz prywatny używany w aplikacji GitHub do odblokowywania dodatkowych funkcji, takich jak publikowanie automatycznych komentarzy PR. **Zalecamy użycie wersji zakodowanej w base64, aby uniknąć problemów ze znakami specjalnymi.** | Nie      | `-----BEGIN RSA...`                |                                                                                 |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | Rozdzielana przecinkami lista uchwytów użytkowników, którzy mają dostęp do adresów URL operacji.                                                                                                                                      | Nie      |                                    | `user1,user2`                                                                   |                                                                                                                                    |
| `TUIST_WEB`                           | Włącz punkt końcowy serwera WWW                                                                                                                                                                                                       | Nie      | `1`                                | `1` lub `0`                                                                     |                                                                                                                                    |

### Konfiguracja bazy danych {#database-configuration}

Następujące zmienne środowiskowe są używane do konfiguracji połączenia z bazą
danych:

| Zmienna środowiskowa                 | Opis                                                                                                                                                                                                                             | Wymagane | Domyślne  | Przykłady                                                              |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Adres URL dostępu do bazy danych Postgres. Należy pamiętać, że adres URL powinien zawierać informacje uwierzytelniające                                                                                                          | Tak      |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | Adres URL dostępu do bazy danych ClickHouse. Należy pamiętać, że adres URL powinien zawierać informacje uwierzytelniające                                                                                                        | Nie      |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | Gdy wartość ta jest prawdziwa, do połączenia z bazą danych używany jest protokół [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security).                                                                                  | Nie      | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | Liczba połączeń, które mają pozostać otwarte w puli połączeń                                                                                                                                                                     | Nie      | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | Interwał (w milisekundach) sprawdzania, czy wszystkie połączenia wyewidencjonowane z puli zajęły więcej niż interwał kolejki [(Więcej informacji)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Nie      | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | Czas progowy (w milisekundach) w kolejce, którego pula używa do określenia, czy powinna zacząć odrzucać nowe połączenia [(Więcej informacji)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)      | Nie      | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | Odstęp czasu w milisekundach pomiędzy kolejnymi opróżnieniami bufora ClickHouse                                                                                                                                                  | Nie      | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | Maksymalny rozmiar bufora ClickHouse w bajtach przed wymuszeniem spłukiwania                                                                                                                                                     | Nie      | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | Liczba procesów bufora ClickHouse do uruchomienia                                                                                                                                                                                | Nie      | `5`       | `5`                                                                    |

### Konfiguracja środowiska uwierzytelniania {#authentication-environment-configuration}

Ułatwiamy uwierzytelnianie za pośrednictwem [dostawców tożsamości
(IdP)](https://en.wikipedia.org/wiki/Identity_provider). Aby z tego skorzystać,
należy upewnić się, że wszystkie niezbędne zmienne środowiskowe dla wybranego
dostawcy są obecne w środowisku serwera. **Brak zmiennych** spowoduje, że Tuist
ominie tego dostawcę.

#### GitHub {#github}

Zalecamy uwierzytelnianie za pomocą aplikacji [GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps),
ale można również użyć aplikacji [OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app).
Upewnij się, że w środowisku serwera znajdują się wszystkie istotne zmienne
środowiskowe określone przez GitHub. Brak zmiennych spowoduje, że Tuist przeoczy
uwierzytelnianie GitHub. Aby poprawnie skonfigurować aplikację GitHub:
- W ustawieniach ogólnych aplikacji GitHub:
    - Skopiuj identyfikator klienta `` i ustaw go jako
      `TUIST_GITHUB_APP_CLIENT_ID.`
    - Utwórz i skopiuj nowy sekret klienta `` i ustaw go jako
      `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Ustaw adres URL wywołania zwrotnego `` jako
      `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` może być
      również adresem IP serwera.
- Wymagane są następujące uprawnienia:
  - Repozytoria:
    - Żądania ściągnięcia: Odczyt i zapis
  - Konta:
    - Adresy e-mail: Tylko do odczytu

W sekcji `Uprawnienia i zdarzenia`'s `Uprawnienia konta` ustaw uprawnienie
`Adresy e-mail` na `Tylko do odczytu`.

Następnie należy ujawnić następujące zmienne środowiskowe w środowisku, w którym
działa serwer Tuist:

| Zmienna środowiskowa             | Opis                                   | Wymagane | Domyślne | Przykłady                                  |
| -------------------------------- | -------------------------------------- | -------- | -------- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | Identyfikator klienta aplikacji GitHub | Tak      |          | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Sekret klienta aplikacji               | Tak      |          | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

Możesz skonfigurować uwierzytelnianie w Google przy użyciu [OAuth
2](https://developers.google.com/identity/protocols/oauth2). W tym celu należy
utworzyć nowe poświadczenia typu OAuth client ID. Podczas tworzenia poświadczeń
wybierz "Aplikacja internetowa" jako typ aplikacji, nazwij ją `Tuist` i ustaw
URI przekierowania na `{base_url}/users/auth/google/callback` gdzie `base_url`
to adres URL, pod którym działa hostowana usługa. Po utworzeniu aplikacji
skopiuj identyfikator klienta i sekret i ustaw je odpowiednio jako zmienne
środowiskowe `GOOGLE_CLIENT_ID` i `GOOGLE_CLIENT_SECRET`.

::: info CONSENT SCREEN SCOPES
<!-- -->
Może być konieczne utworzenie ekranu zgody. W tym celu należy dodać zakresy
`userinfo.email` i `openid` oraz oznaczyć aplikację jako wewnętrzną.
<!-- -->
:::

#### Okta {#okta}

Możesz włączyć uwierzytelnianie w Okta za pomocą protokołu [OAuth
2.0](https://oauth.net/2/). Będziesz musiał [utworzyć
aplikację](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)
w Okta zgodnie z <LocalizedLink href="/guides/integrations/sso#okta"> tymi instrukcjami</LocalizedLink>.

Po uzyskaniu identyfikatora klienta i hasła tajnego podczas konfigurowania
aplikacji Okta należy ustawić następujące zmienne środowiskowe:

| Zmienna środowiskowa         | Opis                                                                                                     | Wymagane | Domyślne | Przykłady |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- | -------- | -------- | --------- |
| `TUIST_OKTA_1_CLIENT_ID`     | Identyfikator klienta do uwierzytelniania w usłudze Okta. Numer powinien być identyfikatorem organizacji | Tak      |          |           |
| `TUIST_OKTA_1_CLIENT_SECRET` | Klucz tajny klienta do uwierzytelniania w usłudze Okta                                                   | Tak      |          |           |

Numer `1` należy zastąpić identyfikatorem organizacji. Zazwyczaj będzie to 1,
ale należy to sprawdzić w bazie danych.

### Konfiguracja środowiska pamięci masowej {#storage-environment-configuration}

Tuist potrzebuje pamięci masowej do przechowywania artefaktów przesłanych za
pośrednictwem interfejsu API.** Aby aplikacja Tuist działała efektywnie,
konieczne jest skonfigurowanie jednego z obsługiwanych rozwiązań pamięci masowej
**.

#### Magazyny zgodne z S3 {#s3compliant-storages}

Do przechowywania artefaktów można użyć dowolnego dostawcy pamięci masowej
zgodnego z S3. Do uwierzytelnienia i skonfigurowania integracji z dostawcą
magazynu wymagane są następujące zmienne środowiskowe:

| Zmienna środowiskowa                                     | Opis                                                                                                                                                                                    | Wymagane | Domyślne                         | Przykłady                                                     |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` lub `AWS_ACCESS_KEY_ID`         | Identyfikator klucza dostępu do uwierzytelniania względem dostawcy pamięci masowej                                                                                                      | Tak      |                                  | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` lub `AWS_SECRET_ACCESS_KEY` | Tajny klucz dostępu do uwierzytelniania wobec dostawcy pamięci masowej                                                                                                                  | Tak      |                                  | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` lub `AWS_REGION`                       | Region, w którym znajduje się zasobnik                                                                                                                                                  | Nie      | `auto`                           | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` lub `AWS_ENDPOINT`                   | Punkt końcowy dostawcy pamięci masowej                                                                                                                                                  | Tak      |                                  | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                   | Nazwa zasobnika, w którym przechowywane będą artefakty.                                                                                                                                 | Tak      |                                  | `tuist-artefakty`                                             |
| `TUIST_S3_CA_CERT_PEM`                                   | Certyfikat CA zakodowany w PEM do weryfikacji połączeń S3 HTTPS. Przydatne w środowiskach z izolacją powietrzną z samopodpisanymi certyfikatami lub wewnętrznymi urzędami certyfikacji. | Nie      | Pakiet CA systemu                | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                               | Czas oczekiwania (w milisekundach) na nawiązanie połączenia z dostawcą pamięci masowej.                                                                                                 | Nie      | `3000`                           | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                               | Limit czasu (w milisekundach) na odebranie danych od dostawcy pamięci masowej.                                                                                                          | Nie      | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                  | Limit czasu (w milisekundach) dla puli połączeń z dostawcą pamięci masowej. Użyj `nieskończoność` dla braku limitu czasu                                                                | Nie      | `5000`                           | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                            | Maksymalny czas bezczynności (w milisekundach) dla połączeń w puli. Użyj `infinity`, aby utrzymać połączenia przy życiu w nieskończoność                                                | Nie      | `nieskończoność`                 | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                     | Maksymalna liczba połączeń na pulę                                                                                                                                                      | Nie      | `500`                            | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                    | Liczba pul połączeń do użycia                                                                                                                                                           | Nie      | Liczba harmonogramów systemowych | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                      | Protokół używany podczas łączenia się z dostawcą pamięci masowej (`http1` lub `http2`).                                                                                                 | Nie      | `http1`                          | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                  | Czy adres URL powinien być skonstruowany z nazwą zasobnika jako subdomena (host wirtualny)?                                                                                             | Nie      | `fałszywy`                       | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
Jeśli dostawcą pamięci masowej jest AWS i chcesz uwierzytelniać się za pomocą
tokena tożsamości sieciowej, możesz ustawić zmienną środowiskową
`TUIST_S3_AUTHENTICATION_METHOD` na `aws_web_identity_token_from_env_vars`, a
Tuist użyje tej metody przy użyciu konwencjonalnych zmiennych środowiskowych
AWS.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
W przypadku Google Cloud Storage należy postępować zgodnie z [tymi
dokumentami](https://cloud.google.com/storage/docs/authentication/managing-hmackeys),
aby uzyskać parę `AWS_ACCESS_KEY_ID` i `AWS_SECRET_ACCESS_KEY`. Zmienna
`AWS_ENDPOINT` powinna być ustawiona na `https://storage.googleapis.com`. Inne
zmienne środowiskowe są takie same, jak w przypadku każdego innego magazynu
zgodnego z S3.

### Konfiguracja poczty e-mail {#email-configuration}

Tuist wymaga funkcji poczty e-mail do uwierzytelniania użytkowników i
powiadomień transakcyjnych (np. resetowania hasła, powiadomień o koncie).
Obecnie **obsługuje tylko Mailgun** jako dostawcę poczty e-mail.

| Zmienna środowiskowa             | Opis                                                                                                                                                                              | Wymagane | Domyślne                                                                            | Przykłady                 |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------- | ------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Klucz API do uwierzytelniania w Mailgun                                                                                                                                           | Tak*     |                                                                                     | `key-1234567890abcdef`    |
| `TUIST_MAILING_DOMAIN`           | Domena, z której będą wysyłane wiadomości e-mail                                                                                                                                  | Tak*     |                                                                                     | `mg.tuist.io`             |
| `TUIST_MAILING_FROM_ADDRESS`     | Adres e-mail, który pojawi się w polu "Od".                                                                                                                                       | Tak*     |                                                                                     | `noreply@tuist.io`        |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Opcjonalny adres reply-to dla odpowiedzi użytkownika                                                                                                                              | Nie      |                                                                                     | `support@tuist.dev`       |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | Pomiń potwierdzenie e-mail dla rejestracji nowych użytkowników. Po włączeniu tej opcji użytkownicy są automatycznie potwierdzani i mogą zalogować się natychmiast po rejestracji. | Nie      | `true` jeśli email nie jest skonfigurowany, `false` jeśli email jest skonfigurowany | `true`, `false`, `1`, `0` |

\* Zmienne konfiguracyjne e-mail są wymagane tylko wtedy, gdy chcesz wysyłać
wiadomości e-mail. Jeśli nie zostaną skonfigurowane, potwierdzenie e-mail
zostanie automatycznie pominięte

::: info SMTP SUPPORT
<!-- -->
Ogólna obsługa SMTP nie jest obecnie dostępna. Jeśli potrzebujesz wsparcia SMTP
dla swojego lokalnego wdrożenia, skontaktuj się z
[contact@tuist.dev](mailto:contact@tuist.dev), aby omówić swoje wymagania.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
W przypadku instalacji lokalnych bez dostępu do Internetu lub konfiguracji
dostawcy poczty e-mail, potwierdzenie e-mail jest domyślnie automatycznie
pomijane. Użytkownicy mogą zalogować się natychmiast po rejestracji. Jeśli masz
skonfigurowaną pocztę e-mail, ale nadal chcesz pominąć potwierdzenie, ustaw
`TUIST_SKIP_EMAIL_CONFIRMATION=true`. Aby wymagać potwierdzenia e-mailem, gdy
e-mail jest skonfigurowany, ustaw `TUIST_SKIP_EMAIL_CONFIRMATION=false`.
<!-- -->
:::

### Konfiguracja platformy Git {#git-platform-configuration}

Tuist może <LocalizedLink href="/guides/server/authentication"> integrować się z platformami Git</LocalizedLink>, aby zapewnić dodatkowe funkcje, takie jak
automatyczne publikowanie komentarzy w pull requestach.

#### GitHub {#platform-github}

Konieczne będzie [utworzenie aplikacji
GitHub](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
Możesz ponownie użyć tej, którą utworzyłeś do uwierzytelniania, chyba że
utworzyłeś aplikację OAuth GitHub. W sekcji `Uprawnienia i zdarzenia`'s
`Uprawnienia repozytorium` należy dodatkowo ustawić uprawnienie `Żądania
ściągnięcia` na `Odczyt i zapis`.

Oprócz `TUIST_GITHUB_APP_CLIENT_ID` i `TUIST_GITHUB_APP_CLIENT_SECRET` potrzebne
będą następujące zmienne środowiskowe:

| Zmienna środowiskowa           | Opis                            | Wymagane | Domyślne | Przykłady                            |
| ------------------------------ | ------------------------------- | -------- | -------- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | Klucz prywatny aplikacji GitHub | Tak      |          | `-----BEGIN RSA PRIVATE KEY-----...` |

## Lokalne testy {#testing-locally}

Zapewniamy kompleksową konfigurację Docker Compose, która obejmuje wszystkie
wymagane zależności do testowania serwera Tuist na komputerze lokalnym przed
wdrożeniem w infrastrukturze:

- PostgreSQL 15 z rozszerzeniem TimescaleDB 2.16 (przestarzałe)
- ClickHouse 25 dla analityków
- ClickHouse Keeper do koordynacji
- MinIO dla pamięci masowej kompatybilnej z S3
- Redis do trwałego przechowywania KV między wdrożeniami (opcjonalnie)
- pgweb do administrowania bazami danych

::: danger LICENSE REQUIRED
<!-- -->
Ważna zmienna środowiskowa `TUIST_LICENSE` jest prawnie wymagana do uruchomienia
serwera Tuist, w tym lokalnych instancji programistycznych. Jeśli potrzebujesz
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

2. Konfiguracja zmiennych środowiskowych:
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

4. Dostęp do serwera pod adresem http://localhost:8080

**Punkty końcowe usługi:**
- Serwer Tuist: http://localhost:8080
- MinIO Console: http://localhost:9003 (poświadczenia: `tuist` /
  `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Wspólne polecenia:**

Sprawdź status usługi:
```bash
docker compose ps
# or: podman compose ps
```

Wyświetlanie dzienników:
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
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Pełna
  konfiguracja Docker Compose
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) -
  Konfiguracja ClickHouse
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - Konfiguracja ClickHouse Keeper
- [.env.example](/server/self-host/.env.example) - Przykładowy plik zmiennych
  środowiskowych

## Wdrożenie {#deployment}

Oficjalny obraz Tuist Docker dostępny jest pod adresem:
```
ghcr.io/tuist/tuist
```

### Pobieranie obrazu Docker {#pulling-the-docker-image}

Obraz można pobrać, wykonując następujące polecenie:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Lub pobrać określoną wersję:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Wdrażanie obrazu Docker {#deploying-the-docker-image}

Proces wdrażania obrazu Docker będzie różnił się w zależności od wybranego
dostawcy chmury i podejścia organizacji do ciągłego wdrażania. Ponieważ
większość rozwiązań i narzędzi chmurowych, takich jak
[Kubernetes](https://kubernetes.io/), wykorzystuje obrazy Docker jako podstawowe
jednostki, przykłady w tej sekcji powinny dobrze pasować do istniejącej
konfiguracji.

::: warning
<!-- -->
Jeśli potok wdrażania wymaga sprawdzenia, czy serwer jest uruchomiony, można
wysłać żądanie HTTP `GET` do `/ready` i potwierdzić kod stanu `200` w
odpowiedzi.
<!-- -->
:::

#### Latać {#fly}

Aby wdrożyć aplikację na platformie [Fly](https://fly.io/), potrzebny będzie
plik konfiguracyjny `fly.toml`. Rozważ wygenerowanie go dynamicznie w ramach
potoku Continuous Deployment (CD). Poniżej znajduje się przykład referencyjny:

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

Następnie można uruchomić `fly launch --local-only --no-deploy`, aby uruchomić
aplikację. Przy kolejnych wdrożeniach, zamiast uruchamiać `fly launch
--local-only`, należy uruchomić `fly deploy --local-only`. Fly.io nie pozwala na
pobieranie prywatnych obrazów Docker, dlatego musimy użyć flagi `--local-only`.


## Metryki Prometeusza {#prometheus-metrics}

Tuist udostępnia metryki Prometheus pod adresem `/metrics`, aby pomóc w
monitorowaniu samodzielnie hostowanej instancji. Metryki te obejmują:

### Metryki klienta HTTP Finch {#finch-metrics}

Tuist używa [Finch](https://github.com/sneako/finch) jako klienta HTTP i
udostępnia szczegółowe dane dotyczące żądań HTTP:

#### Metryki żądań
- `tuist_prom_ex_finch_request_count_total` - Całkowita liczba żądań Finch
  (licznik)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Czas trwania żądań HTTP
  (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Wiadra: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Całkowita liczba
  wyjątków żądań Finch (licznik)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### Metryki kolejki puli połączeń
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Czas oczekiwania w kolejce
  puli połączeń (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Wiadra: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Czas bezczynności
  połączenia przed użyciem (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Wiadra: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Całkowita liczba wyjątków
  kolejki Finch (licznik)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Metryki połączeń
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Czas spędzony na
  nawiązywaniu połączenia (histogram)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`, `error`
  - Wiadra: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Całkowita liczba prób połączenia
  (licznik)
  - Etykiety: `finch_name`, `scheme`, `host`, `port`

#### Wysyłanie metryk
- `tuist_prom_ex_finch_send_duration_milliseconds` - Czas wysłania żądania
  (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Wiadra: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Czas bezczynności
  połączenia przed wysłaniem (histogram)
  - Etykiety: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Wiadra: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Wszystkie metryki histogramów udostępniają warianty `_bucket`, `_sum` i `_count`
do szczegółowej analizy.

### Inne wskaźniki

Oprócz metryk Finch, Tuist udostępnia metryki dla:
- Wydajność maszyny wirtualnej BEAM
- Niestandardowe metryki logiki biznesowej (magazyn, konta, projekty itp.).
- Wydajność bazy danych (w przypadku korzystania z infrastruktury hostowanej
  przez Tuist)

## Operacje {#operations}

Tuist udostępnia zestaw narzędzi pod adresem `/ops/`, których można użyć do
zarządzania instancją.

::: warning Authorization
<!-- -->
Tylko osoby, których uchwyty są wymienione w zmiennej środowiskowej
`TUIST_OPS_USER_HANDLES` mogą uzyskać dostęp do punktów końcowych `/ops/`.
<!-- -->
:::

- **Błędy (`/ops/errors`):** Możesz wyświetlić nieoczekiwane błędy, które
  wystąpiły w aplikacji. Jest to przydatne do debugowania i zrozumienia, co
  poszło nie tak i możemy poprosić Cię o udostępnienie nam tych informacji,
  jeśli napotkasz problemy.
- **Dashboard (`/ops/dashboard`):** Możesz wyświetlić pulpit nawigacyjny, który
  zapewnia wgląd w wydajność i stan aplikacji (np. zużycie pamięci, uruchomione
  procesy, liczbę żądań). Ten pulpit nawigacyjny może być bardzo przydatny, aby
  zrozumieć, czy używany sprzęt jest wystarczający do obsługi obciążenia.
