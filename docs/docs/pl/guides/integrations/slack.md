---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Integracja ze Slackiem {#slack}

Jeśli Twoja organizacja korzysta ze Slacka, możesz zintegrować Tuist, aby
wyświetlać analizy bezpośrednio w kanałach. Dzięki temu monitorowanie przestaje
być czymś, o czym Twój zespół musi pamiętać, a staje się czymś, co po prostu się
dzieje. Na przykład Twój zespół może otrzymywać codzienne podsumowania dotyczące
wydajności kompilacji, wskaźników trafień w pamięci podręcznej lub trendów
dotyczących rozmiaru pakietów.

## Konfiguracja {#setup}

### Połącz swoje miejsce pracy w Slacku {#connect-workspace}

Najpierw połącz swoje środowisko pracy Slack z kontem Tuist w zakładce
„Integracje” ( `)`:

![Obraz przedstawiający zakładkę integracji z połączeniem ze
Slackiem](/images/guides/integrations/slack/integrations.png)

Kliknij „ **” (Połącz z Slackiem)**, aby autoryzować Tuist do publikowania
wiadomości w Twoim obszarze roboczym. Spowoduje to przekierowanie do strony
autoryzacji Slacka, gdzie możesz zatwierdzić połączenie.

> [!UWAGA] ZATWIERDZENIE ADMINISTRATORA SLACKA
> <!-- -->
> Jeśli Twoja przestrzeń robocza Slacka ogranicza instalację aplikacji, może być
> konieczne uzyskanie zgody od administratora Slacka. Slack przeprowadzi Cię
> przez proces składania wniosku o zgodę podczas autoryzacji.
> <!-- -->

### Raporty z projektu {#project-reports}

Po podłączeniu Slacka skonfiguruj raporty dla każdego projektu w zakładce
powiadomień w ustawieniach projektu:

![Obraz przedstawiający ustawienia powiadomień z konfiguracją raportów
Slacka](/images/guides/integrations/slack/notifications-settings.png)

Możesz skonfigurować:
- **Kanał**: Wybierz kanał Slacka, na który mają być wysyłane raporty
- ****: Wybierz dni tygodnia, w które chcesz otrzymywać raporty
- ****: Ustawianie godziny

> [!OSTRZEŻENIE] KANAŁY PRYWATNE
> <!-- -->
> Aby aplikacja Tuist Slack mogła publikować wiadomości na prywatnym kanale,
> musisz najpierw dodać bota Tuist do tego kanału. W Slacku otwórz prywatny
> kanał, kliknij nazwę kanału, aby otworzyć ustawienia, wybierz „Integracje”,
> następnie „Dodaj aplikacje” i wyszukaj Tuist.
> <!-- -->

Po skonfigurowaniu Tuist wysyła automatyczne codzienne raporty na wybrany kanał
Slacka:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Zasady dotyczące alertów {#alert-rules}

Otrzymuj powiadomienia w Slacku dzięki regułom alertów, gdy kluczowe wskaźniki
ulegną znacznemu pogorszeniu, aby jak najszybciej wykrywać spowolnienia
kompilacji, pogorszenie jakości pamięci podręcznej lub spowolnienia testów,
minimalizując wpływ na produktywność zespołu.

Aby utworzyć regułę alertu, przejdź do ustawień powiadomień swojego projektu i
kliknij „ **” (Ustawienia powiadomień) > „Add alert rule” (Dodaj regułę alertu)
> „** ” (Uwagi dotyczące tłumaczenia):

Możesz skonfigurować:
- **Nazwa**: Opisowa nazwa alertu
- **Kategoria**: Co mierzyć (czas kompilacji, czas testowania czy współczynnik
  trafień w pamięci podręcznej)
- **** a metryki: Jak agregować dane (p50, p90, p99 lub średnia)
- **Odchylenie**: Procentowa zmiana, która powoduje wygenerowanie alertu
- **** a okna ruchomego: ile ostatnich przebiegów należy porównać
- **Kanał Slacka**: Gdzie wysłać powiadomienie

Na przykład możesz utworzyć alert, który uruchamia się, gdy czas kompilacji p90
wydłuży się o ponad 20% w porównaniu z poprzednimi 100 kompilacjami.

Gdy zostanie wygenerowany alert, na kanale Slacka pojawi się następująca
wiadomość:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!UWAGA] OKRES OCHŁODZENIA
> <!-- -->
> Po wywołaniu alertu nie zostanie on ponownie uruchomiony dla tej samej reguły
> przez 24 godziny. Zapobiega to zmęczeniu powiadomieniami, gdy wskaźnik
> pozostaje na podwyższonym poziomie.
> <!-- -->

### Niesprawne alerty testowe {#flaky-test-alerts}

Otrzymuj natychmiastowe powiadomienia, gdy test stanie się niestabilny. W
przeciwieństwie do reguł alertów opartych na metrykach, które porównują okna
kroczące, alerty o niestabilnych testach uruchamiają się w momencie, gdy Tuist
wykryje nowy niestabilny test, pomagając Ci wykryć niestabilność testów, zanim
wpłynie ona na Twój zespół.

Aby utworzyć regułę alertu o niestabilnym teście, przejdź do ustawień
powiadomień swojego projektu i kliknij „ **” (Ustawienia powiadomień) Dodaj
regułę alertu o niestabilnym teście**:

Możesz skonfigurować:
- **Nazwa**: Opisowa nazwa alertu
- **Próg wyzwalający**: Minimalna liczba niestabilnych uruchomień w ciągu
  ostatnich 30 dni wymagana do wyzwolenia alertu
- **Kanał Slacka**: Gdzie wysłać powiadomienie

Gdy test stanie się niestabilny i osiągnie próg, otrzymasz powiadomienie z
bezpośrednim linkiem umożliwiającym zbadanie przypadku testowego:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## Instalacje lokalne {#on-premise}

W przypadku lokalnych instalacji Tuist należy utworzyć własną aplikację Slack i
skonfigurować niezbędne zmienne środowiskowe.

### Utwórz aplikację Slack {#create-slack-app}

1. Przejdź do [strony aplikacji Slack API](https://api.slack.com/apps) i kliknij
   „ **” (Utwórz nową aplikację).**
2. Wybierz opcję „ **” (Zainstaluj aplikację) z manifestu aplikacji** i wybierz
   obszar roboczy, w którym chcesz zainstalować aplikację
3. Wklej poniższy manifest, zastępując adres URL przekierowania adresem URL
   swojego serwera Tuist:

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. Sprawdź i utwórz aplikację

### Skonfiguruj zmienne środowiskowe {#configure-environment}

Ustaw następujące zmienne środowiskowe na serwerze Tuist:

- `SLACK_CLIENT_ID` - Identyfikator klienta z strony Informacje podstawowe
  Twojej aplikacji Slack
- `SLACK_CLIENT_SECRET` - Tajny klucz klienta z strony Informacje podstawowe
  Twojej aplikacji Slack
