---
{
  "title": "Previews",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Делитесь мобильными и десктопными приложениями, а также инструментами командной строки с помощью Tuist Previews, чтобы коллеги могли опробовать сборку без её локальной пересборки."
}
---
# Previews {#previews}

Tuist Previews позволяют коллегам тестировать мобильные приложения, десктопные приложения и инструменты командной строки без их локальной пересборки. Опубликуйте сборку в вашем проекте Tuist, а затем поделитесь ссылкой на превью.

## Что можно просматривать {#what-you-can-preview}

- **Мобильные приложения:** Android APK и пакеты приложений Apple или IPA. Поддерживаемые устройства, симуляторы и требования к подписи зависят от рабочего процесса публикации.
- **Десктопные приложения:** пакеты приложений macOS.
- **Инструменты командной строки:** исполняемые файлы macOS или Linux, отдельно или вместе с их зависимостями.

Смотрите <.localized_link href="/guides/features/previews/types">Поддерживаемые типы</.localized_link> для требований к упаковке и совместимости. Тип артефакта определяет, где может запускаться превью; он не диктует, какая система сборки его производит.

## Публикация превью {#publish-a-preview}

Выберите свою систему сборки для команд настройки и публикации:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Делитесь приложениями из существующих проектов Xcode или проектов, сгенерированных Tuist."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Делитесь приложениями Android и нативными инструментами командной строки из проектов Gradle."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="Делитесь приложениями Android, приложениями Apple и инструментами командной строки с помощью сопутствующих правил Bazel."
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Struo"
    details="Публикуйте подходящие приложения Android, симулятора Apple и macOS с помощью нативного провайдера артефактов Struo."
    link="/guides/features/previews/struo"
  />
</.home_cards>

Если у вас уже есть поддерживаемая сборка, используйте <.localized_link href="/cli/share">`tuist share`</.localized_link> для её публикации без интеграции с системой сборки. Требования к упаковке и подписи всё ещё применяются.

## Запуск превью {#run-a-preview}

Получателям не нужна система сборки, которая создала превью. Выберите способ доступа к совместимой сборке:

<.home_cards>
  <.home_card
    title="CLI"
    details="Запускайте мобильные приложения, приложения macOS и превью командной строки с помощью tuist run."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="Приложение macOS"
    details="Запускайте совместимые превью Apple через приложение Tuist в строке меню."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="Приложение iPhone"
    details="Находите и открывайте свои превью Apple на iPhone."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## Видимость {#visibility}

Превью используют видимость проекта по умолчанию. Приватные превью требуют аутентификации и доступа к проекту. Делайте превью публичными в настройках проекта только тогда, когда сборку можно поделиться с кем угодно. Публичная видимость не обходит требования платформы к подписи или установке на устройство.

## Треки {#tracks}

Треки организуют превью в именованные группы, например `beta` для внутренних тестировщиков или `nightly` для автоматизированных сборок. Укажите трек в команде публикации для вашего рабочего процесса; треки создаются лениво при первом использовании. Используйте их для группировки превью по назначению и фильтрации превью в панели управления Tuist.

## Значок README {#readme-badge}

Добавьте значок в `README` вашего репозитория, который указывает на последнее превью:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Замените хендлы аккаунта и проекта на свои собственные:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Если проект содержит несколько приложений с разными идентификаторами пакетов, добавьте параметр запроса `bundle-id`, чтобы выбрать приложение:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
