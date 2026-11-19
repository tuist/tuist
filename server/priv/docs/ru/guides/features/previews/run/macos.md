---
{
  "title": "Запуск превью через приложение для macOS",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Используйте приложение Tuist в строке меню macOS для запуска совместимых превью Apple на устройствах и симуляторах."
}
---
# Запуск превью через приложение для macOS

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Для Apple-превью приложение Tuist в строке меню macOS является альтернативой CLI, независимо от того, была ли сборка выполнена в Xcode, Bazel или Struo. Требования к подписи и допустимости в процессе публикации остаются в силе.

## Установка {#install}

[Скачайте приложение](https://tuist.dev/download) или установите его с помощью `brew install --cask tuist/tuist/tuist`.

## Запуск сборки {#run-a-build}

Выберите совместимое устройство или симулятор в приложении строки меню, затем нажмите **Run** на странице превью.

Приложение для macOS сначала запрашивает последнее совместимое превью для каждого приложения. На старых серверах, которые выбирают отдельные приложения перед применением фильтров платформы, оно переходит к постраничной истории, не устанавливая ограничение, которое могло бы скрыть доступную сборку.

Информацию о доступе и организации см. в разделе <.localized_link href="/guides/features/previews#visibility">видимость и треки</.localized_link>.
