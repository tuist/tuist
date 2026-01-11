---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Integracja z usługą Slack {#slack}

Jeśli Twoja organizacja korzysta ze Slacka, możesz zintegrować Tuist, aby
wyświetlać spostrzeżenia bezpośrednio w swoich kanałach. Dzięki temu
monitorowanie zmieni się z czegoś, o czym zespół musi pamiętać, w coś, co po
prostu się dzieje. Na przykład, zespół może otrzymywać codzienne podsumowania
wydajności kompilacji, współczynników trafień pamięci podręcznej lub trendów
wielkości pakietów.

## Konfiguracja {#setup}

### Połącz swój obszar roboczy Slack {#connect-workspace}

Najpierw połącz swój obszar roboczy Slack z kontem Tuist w zakładce
`Integrations`:

![Obraz przedstawiający kartę integracji z połączeniem
Slack](/images/guides/integrations/slack/integrations.png)

Kliknij **Connect Slack**, aby autoryzować Tuist do publikowania wiadomości w
Twojej przestrzeni roboczej. Spowoduje to przekierowanie na stronę autoryzacji
Slack, gdzie można zatwierdzić połączenie.

> [UWAGA] ZATWIERDZENIE ADMINISTRATORA SLACK Jeśli przestrzeń robocza Slack
> ogranicza instalacje aplikacji, może być konieczne zażądanie zatwierdzenia od
> administratora Slack. Slack poprowadzi Cię przez proces żądania zatwierdzenia
> podczas autoryzacji.

### Raporty z projektów {#project-reports}

Po podłączeniu aplikacji Slack skonfiguruj raporty dla każdego projektu w
zakładce powiadomień w ustawieniach projektu:

![Obraz przedstawiający ustawienia powiadomień z konfiguracją raportów
Slack](/images/guides/integrations/slack/notifications-settings.png)

Można skonfigurować:
- **Kanał**: Wybierz, który kanał Slack ma otrzymywać raporty
- **Harmonogram**: Wybierz dni tygodnia, w które chcesz otrzymywać raporty
- **Czas**: Ustawianie pory dnia

Po skonfigurowaniu Tuist wysyła automatyczne raporty dzienne na wybrany kanał
Slack:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Zasady alertów {#alert-rules}

Otrzymuj powiadomienia w Slack za pomocą reguł alertów, gdy kluczowe wskaźniki
znacznie spadną, aby pomóc Ci jak najszybciej wykryć wolniejsze kompilacje,
degradację pamięci podręcznej lub spowolnienia testów, minimalizując wpływ na
produktywność zespołu.

Aby utworzyć regułę alertu, przejdź do ustawień powiadomień projektu i kliknij
**Dodaj regułę alertu**:

Można skonfigurować:
- **Nazwa**: Opisowa nazwa wpisu
- **Kategoria**: Co mierzyć (czas trwania kompilacji, czas trwania testu czy
  współczynnik trafień pamięci podręcznej)?
- **Metryka**: Jak agregować dane (p50, p90, p99 lub średnia)?
- **Odchylenie**: Zmiana procentowa, która uruchamia alert
- **Rolling window**: Ile ostatnich przebiegów należy porównać
- **Kanał Slack**: Gdzie wysłać powiadomienie

Na przykład można utworzyć alert, który zostanie uruchomiony, gdy czas trwania
kompilacji p90 wzrośnie o ponad 20% w porównaniu do poprzednich 100 kompilacji.

Gdy alert zostanie wyzwolony, otrzymasz wiadomość podobną do tej na swoim kanale
Slack:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [Po wyzwoleniu alertu nie zostanie on uruchomiony ponownie dla tej samej
> reguły przez 24 godziny. Zapobiega to zmęczeniu powiadomieniami, gdy wskaźnik
> pozostaje podwyższony.

## Instalacje lokalne {#on-premise}

W przypadku lokalnych instalacji Tuist konieczne będzie utworzenie własnej
aplikacji Slack i skonfigurowanie niezbędnych zmiennych środowiskowych.

### Utwórz aplikację Slack {#create-slack-app}

1. Przejdź do strony [Slack API Apps](https://api.slack.com/apps) i kliknij
   **Create New App.**
2. Wybierz **Z manifestu aplikacji** i wybierz obszar roboczy, w którym chcesz
   zainstalować aplikację.
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

4. Przeglądanie i tworzenie aplikacji

### Konfiguracja zmiennych środowiskowych {#configure-environment}

Ustaw następujące zmienne środowiskowe na serwerze Tuist:

- `SLACK_CLIENT_ID` - Identyfikator klienta ze strony podstawowych informacji
  aplikacji Slack.
- `SLACK_CLIENT_SECRET` - Sekret klienta ze strony podstawowych informacji
  aplikacji Slack.
