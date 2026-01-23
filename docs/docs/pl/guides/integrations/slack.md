---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Integracja ze Slackiem {#slack}

Jeśli Twoja organizacja korzysta ze Slacka, możesz zintegrować Tuist, aby
wyświetlać informacje bezpośrednio na swoich kanałach. Dzięki temu monitorowanie
przestaje być czymś, o czym Twój zespół musi pamiętać, a staje się czymś, co po
prostu się dzieje. Na przykład Twój zespół może otrzymywać codzienne
podsumowania wydajności kompilacji, wskaźników trafień w pamięci podręcznej lub
trendów dotyczących rozmiaru pakietów.

## Konfiguracja {#setup}

### Połącz swoje miejsce pracy Slack {#connect-workspace}

Najpierw połącz swoje konto Slack z kontem Tuist w zakładce „ `” (Integracje) „`
” (Integracje):

![Obraz przedstawiający zakładkę integracji z połączeniem
Slack](/images/guides/integrations/slack/integrations.png)

Kliknij „ **” (Połącz z moim Slackiem). Połącz „** ” (Połącz z moim Slackiem),
aby upoważnić Tuist do publikowania wiadomości w Twoim obszarze roboczym.
Spowoduje to przekierowanie do strony autoryzacyjnej Slacka, gdzie możesz
zatwierdzić połączenie.

> [!UWAGA] ZATWIERDZENIE ADMINISTRATORA SLACK
> <!-- -->
> Jeśli Twoje miejsce pracy Slack ogranicza instalację aplikacji, może być
> konieczne zwrócenie się o zgodę do administratora Slack. Slack poprowadzi Cię
> przez proces uzyskiwania zgody podczas autoryzacji.
> <!-- -->

### Raporty z projektu {#project-reports}

Po połączeniu Slacka skonfiguruj raporty dla każdego projektu w zakładce
powiadomień w ustawieniach projektu:

![Obraz przedstawiający ustawienia powiadomień z konfiguracją raportów
Slack](/images/guides/integrations/slack/notifications-settings.png)

Możesz skonfigurować:
- **Kanał**: Wybierz kanał Slack, na który będą wysyłane raporty.
- **Harmonogram**: Wybierz dni tygodnia, w które chcesz otrzymywać raporty.
- ****: Ustaw porę dnia

> [!OSTRZEŻENIE] KANAŁY PRYWATNE
> <!-- -->
> Aby aplikacja Tuist Slack mogła publikować wiadomości w prywatnym kanale,
> musisz najpierw dodać bota Tuist do tego kanału. W Slacku otwórz prywatny
> kanał, kliknij nazwę kanału, aby otworzyć ustawienia, wybierz „Integracje”, a
> następnie „Dodaj aplikacje” i wyszukaj Tuist.
> <!-- -->

Po skonfigurowaniu Tuist wysyła automatyczne codzienne raporty do wybranego
kanału Slack:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Reguły alertów {#alert-rules}

Otrzymuj powiadomienia w Slacku dzięki regułom alertów, gdy kluczowe wskaźniki
ulegną znacznemu pogorszeniu, aby jak najszybciej wykrywać spowolnienia
kompilacji, degradację pamięci podręcznej lub spowolnienia testów, minimalizując
wpływ na produktywność zespołu.

Aby utworzyć regułę alertu, przejdź do ustawień powiadomień projektu i kliknij „
**” (Dodaj regułę alertu)**:

Możesz skonfigurować:
- **Nazwa**: opisowa nazwa alertu
- **Kategoria**: Co mierzyć (czas trwania kompilacji, czas trwania testu lub
  współczynnik trafień w pamięci podręcznej)
- **** metryczny: Jak agregować dane (p50, p90, p99 lub średnia)
- **Odchylenie**: Procentowa zmiana, która wyzwala alert.
- **** a okna przesuwnego: ile ostatnich przebiegów należy porównać
- **Kanał Slack**: Gdzie wysłać powiadomienie

Na przykład możesz utworzyć alert, który zostanie wyzwolony, gdy czas trwania
kompilacji p90 wzrośnie o ponad 20% w porównaniu z poprzednimi 100 kompilacjami.

Gdy pojawi się alert, na kanale Slack pojawi się następujący komunikat:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!UWAGA] OKRES WYŁĄCZENIA
> <!-- -->
> Po uruchomieniu alertu nie zostanie on ponownie uruchomiony dla tej samej
> reguły przez 24 godziny. Zapobiega to zmęczeniu powiadomieniami, gdy wskaźnik
> pozostaje podwyższony.
> <!-- -->

### Nieprawidłowe alerty testowe {#flaky-test-alerts}

Otrzymuj natychmiastowe powiadomienia, gdy test stanie się niestabilny. W
przeciwieństwie do reguł alertów opartych na metrykach, które porównują okna
kroczące, alerty o niestabilnych testach są uruchamiane w momencie wykrycia
przez Tuist nowego niestabilnego testu, co pomaga wykryć niestabilność testu,
zanim wpłynie ona na pracę zespołu.

Aby utworzyć regułę alertu o niestabilnym teście, przejdź do ustawień
powiadomień projektu i kliknij „ **” (Dodaj regułę alertu o niestabilnym
teście).**:

Możesz skonfigurować:
- **Nazwa**: opisowa nazwa alertu
- **Próg wyzwalający**: minimalna liczba niestabilnych uruchomień w ciągu
  ostatnich 30 dni wymagana do wyzwolenia alertu.
- **Kanał Slack**: Gdzie wysłać powiadomienie

Gdy test stanie się niestabilny i osiągnie próg, otrzymasz powiadomienie z
bezpośrednim linkiem umożliwiającym zbadanie przypadku testowego:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## Instalacje lokalne {#on-premise}

W przypadku lokalnych instalacji Tuist należy utworzyć własną aplikację Slack i
skonfigurować niezbędne zmienne środowiskowe.

### Utwórz aplikację Slack {#create-slack-app}

1. Przejdź do strony [Slack API Apps](https://api.slack.com/apps) i kliknij „
   **” (Zaloguj się do Slacka). Utwórz nową aplikację.**
2. Wybierz opcję „ **” (Zainstaluj aplikację) z manifestu aplikacji** i wybierz
   obszar roboczy, w którym chcesz zainstalować aplikację.
3. Wklej poniższy manifest, zastępując adres URL przekierowania adresem URL
   serwera Tuist:

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

4. Sprawdź i utwórz aplikację.

### Skonfiguruj zmienne środowiskowe {#configure-environment}

Ustaw następujące zmienne środowiskowe na serwerze Tuist:

- `SLACK_CLIENT_ID` - Identyfikator klienta ze strony podstawowych informacji
  aplikacji Slack.
- `SLACK_CLIENT_SECRET` - Tajny klucz klienta ze strony podstawowych informacji
  aplikacji Slack.
