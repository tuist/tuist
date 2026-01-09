---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Интеграция со Slack {#slack}

Если ваша организация использует Slack, вы можете интегрировать Tuist для
получения информации непосредственно в ваших каналах. Таким образом, мониторинг
превращается из того, что ваша команда должна помнить о необходимости делать, в
то, что просто происходит. Например, ваша команда может ежедневно получать
сводки о производительности сборки, частоте попаданий в кэш или тенденциях
изменения размера пакетов.

## Настройка {#setup}

### Подключите рабочее пространство Slack {#connect-workspace}

Сначала подключите рабочее пространство Slack к учетной записи Tuist на вкладке
`Integrations`:

![Изображение, показывающее вкладку "Интеграции" с подключением
Slack](/images/guides/integrations/slack/integrations.png)

Нажмите **Подключить Slack**, чтобы разрешить Tuist публиковать сообщения в
вашем рабочем пространстве. Это перенаправит вас на страницу авторизации Slack,
где вы сможете одобрить подключение.

> [!ПРИМЕЧАНИЕ] УТВЕРЖДЕНИЕ АДМИНИСТРАТОРА SLACK Если рабочее пространство Slack
> ограничивает установку приложений, вам может потребоваться запросить
> разрешение у администратора Slack. Slack проведет вас через процесс запроса
> одобрения во время авторизации.

### Отчеты по проектам {#project-reports}

After connecting Slack, configure reports for each project in the project
settings' notifications tab:

![An image that shows the notifications settings with Slack report
configuration](/images/guides/integrations/slack/notifications-settings.png)

Вы можете настроить:
- **Канал**: Выберите, какой канал Slack получает отчеты
- **Расписание**: Выберите дни недели для получения отчетов
- **Время**: установка времени суток

После настройки Tuist отправляет автоматические ежедневные отчеты в выбранный
вами канал Slack:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Alert rules {#alert-rules}

Get notified in Slack with alert rules when key metrics significantly regress to
help you catch slower builds, cache degradation, or test slowdowns as soon as
possible, minimizing the impact on your team's productivity.

To create an alert rule, go to your project's notification settings and click
**Add alert rule**:

Вы можете настроить:
- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit
  rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: Where to send the alert

For example, you might create an alert that triggers when the p90 build duration
increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack
channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD After an alert triggers, it won't fire again for the
> same rule for 24 hours. This prevents notification fatigue when a metric stays
> elevated.

## Местные установки {#on-premise}

Для локальных установок Tuist вам нужно будет создать собственное приложение
Slack и настроить необходимые переменные окружения.

### Создайте приложение Slack {#create-slack-app}

1. Перейдите на страницу [Slack API Apps](https://api.slack.com/apps) и нажмите
   **Создать новое приложение.**
2. Выберите **Из манифеста приложений** и выберите рабочую область, в которую вы
   хотите установить приложение.
3. Вставьте следующий манифест, заменив URL-адрес перенаправления на URL-адрес
   вашего сервера Tuist:

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

4. Обзор и создание приложения

### Настройка переменных окружения {#configure-environment}

Установите следующие переменные окружения на сервере Tuist:

- `SLACK_CLIENT_ID` - идентификатор клиента со страницы основной информации
  вашего приложения Slack.
- `SLACK_CLIENT_SECRET` - Секрет клиента со страницы основной информации вашего
  приложения Slack.
