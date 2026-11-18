---
{
  "title": "Запуск превью с помощью приложения для macOS",
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

Для Apple-превью приложение Tuist в строке меню macOS является альтернативой CLI, независимо от того, была ли сборка выполнена в Xcode, Bazel или Once. Требования к подписи и условиям публикации остаются в силе.

## Установка {#install}

[Скачать приложение](https://tuist.dev/download) или установить его с помощью `brew install --cask tuist/tuist/tuist`.

## Запуск сборки {#run-a-build}

Выберите совместимое устройство или симулятор в приложении строки меню, затем нажмите **Run** на странице превью.

Приложение для macOS сначала запрашивает последнее совместимое превью для каждого приложения. На старых серверах, которые выбирают отдельные приложения до применения фильтров платформы, оно переходит к постраничной истории без установки ограничения, которое могло бы скрыть доступную сборку.

Подробнее о доступе и организации см. <.localized_link href="/guides/features/previews#visibility">видимость и треки</.localized_link>.
