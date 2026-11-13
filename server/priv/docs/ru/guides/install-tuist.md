---
{
  "title": "Установка Tuist",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Установите интерфейс командной строки Tuist на macOS или Linux с помощью mise или Homebrew и зафиксируйте версию для команд и непрерывной интеграции."
}
---
# Установка Tuist {#install-tuist}

Интерфейс командной строки Tuist работает на **macOS** и **Linux** и подключает ваши проекты Xcode, сгенерированные проекты, Gradle, Bazel и Rust к инфраструктуре кэширования, аналитики и раннеров Tuist. Хотя вы можете собрать Tuist из [исходного кода](https://github.com/tuist/tuist), мы рекомендуем один из способов установки ниже, чтобы обеспечить корректную и проверяемую установку. Проекты на Elixir используют вместо этого Hex-пакет `tuist_ex` и не требуют CLI.

## Mise {#recommended-mise}

> [!NOTE]
> Если у вас не установлен Mise, сначала следуйте [руководству по началу работы](https://mise.jdx.dev/getting-started.html). Mise — рекомендуемая альтернатива [Homebrew](https://brew.sh), если вы команда или организация, которой нужно гарантировать детерминированные версии инструментов в разных окружениях.


В отличие от таких инструментов, как Homebrew, которые устанавливают и активируют одну версию инструмента глобально, **Mise закрепляет версию** либо глобально, либо в рамках проекта. Выполните `mise use`, чтобы установить и активировать Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Если вы клонируете проект, в котором версия Tuist уже закреплена в `mise.toml`, выполните `mise install`, чтобы установить её.

> [!TIP]
> `tuist@latest` разрешается до последней **стабильной** версии. Tuist также публикует предварительные сборки canary и release candidate; они доступны только по явному выбору и никогда не выбираются через `latest`. См. <.localized_link href="/cli/release/channels">Каналы релизов</.localized_link>, чтобы узнать, как закрепить стабильную ветку, которой можно доверять, и как подключить предварительные релизы.

<details>
<summary>Поддержка Linux</summary>

На Linux Tuist доступен исключительно через Mise. Команды, зависящие от Xcode (например, `tuist generate`), недоступны на Linux, но платформенно-независимые команды, такие как `tuist inspect bundle`, работают как ожидается.

</details>


## Homebrew (только macOS) {#recommended-homebrew}

Вы можете установить Tuist с помощью [Homebrew](https://brew.sh) и [наших формул](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **Проверка подлинности бинарных файлов**
>
> Вы можете убедиться, что бинарные файлы вашей установки собраны нами, выполнив следующую команду, которая проверяет, что команда сертификата равна `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, см. <.localized_link href="/guides/integrations/http-proxy">руководство по HTTP-прокси</.localized_link>.

## Следующие шаги {#next-steps}

- Следуйте <.localized_link href="/guides/get-started">руководству по началу работы</.localized_link>, чтобы подключить ваш проект к Tuist.
- Изучите [инфраструктуру сборок Tuist для инженерных команд и AI-агентов](https://tuist.dev), чтобы получить более полное представление о продукте.
