---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Установка Tuist {#install-tuist}

Интерфейс командной строки Tuist работает на **macOS** и **Linux** и подключает ваши проекты Xcode, сгенерированные проекты, а также проекты Gradle и Bazel к инфраструктуре кэширования, аналитики и выполнения Tuist. Хотя вы можете собрать Tuist из [исходного кода](https://github.com/tuist/tuist), мы рекомендуем один из приведенных ниже способов установки, чтобы обеспечить корректную и проверяемую установку.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> Если у вас не установлен Mise, сначала ознакомьтесь с [руководством по началу работы](https://mise.jdx.dev/getting-started.html). Mise — рекомендуемая альтернатива [Homebrew](https://brew.sh), если вы команда или организация, которой необходимо гарантировать детерминированные версии инструментов в разных средах.


В отличие от таких инструментов, как Homebrew, которые устанавливают и активируют одну версию инструмента глобально, **Mise закрепляет версию** либо глобально, либо в рамках проекта. Выполните `mise use`, чтобы установить и активировать Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Если вы клонируете проект, в котором версия Tuist уже закреплена в `mise.toml`, выполните `mise install`, чтобы установить ее.

> [!TIP]
> `tuist@latest` разрешается в последнюю **стабильную** версию. Tuist также публикует предварительные сборки canary и release candidate; они доступны только по явному выбору и никогда не разрешаются через `latest`. См. <.localized_link href="/cli/release-channels">Каналы выпусков</.localized_link>, чтобы узнать, как закрепить надежную стабильную ветку и как подключиться к предварительным выпускам.

<details>
<summary>Поддержка Linux</summary>

На Linux Tuist доступен исключительно через Mise. Команды, зависящие от Xcode (например, `tuist generate`), недоступны на Linux, но платформонезависимые команды, такие как `tuist inspect bundle`, работают как ожидается.

</details>


### <a href="https://brew.sh">Homebrew</a> (только macOS) {#recommended-homebrew}

Вы можете установить Tuist с помощью [Homebrew](https://brew.sh) и [наших формул](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **Проверка подлинности бинарных файлов**
>
> Вы можете убедиться, что бинарные файлы вашей установки собраны нами, выполнив следующую команду, которая проверяет, принадлежит ли сертификат команде `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP-прокси {#http-proxy}

Если ваша сеть направляет исходящий трафик через HTTP-прокси, см. <.localized_link href="/guides/integrations/http-proxy">Руководство по HTTP-прокси</.localized_link>.
