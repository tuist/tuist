---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Проект Xcode {#xcode-project}

Чтобы добавить пакеты с помощью реестра в проект Xcode, используйте стандартный
пользовательский интерфейс Xcode. Вы можете искать пакеты в реестре, нажав на
кнопку `+` на вкладке `Package Dependencies` в Xcode. Если пакет доступен в
реестре, в правом верхнем углу вы увидите `tuist.dev` реестр:

![Добавление зависимостей
пакетов](/images/guides/features/build/registry/registry-add-package.png)

::: info
<!-- -->
В настоящее время Xcode не поддерживает автоматическую замену пакетов управления
исходным кодом на их эквиваленты в реестре. Вам придется вручную удалить пакет
управления исходным кодом и добавить пакет реестра, чтобы ускорить решение
проблемы.
<!-- -->
:::
