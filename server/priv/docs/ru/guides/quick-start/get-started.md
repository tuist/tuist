---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Начало работы {#get-started}

Самый простой способ начать работу с Tuist – в любой директории или в директории
вашего проекта или рабочей области Xcode:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Команда пошагово проведёт вас по шагам для
<LocalizedLink href="/guides/features/projects">создания сгенерированного проекта</LocalizedLink> или интеграции существующего проекта или рабочей области
Xcode. Это поможет вам подключить вашу среду к удаленному серверу, предоставляя
доступ к таким функциям, как
<LocalizedLink href="/guides/features/selective-testing">выборочное тестирование</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">предварительные просмотры</LocalizedLink>, и
<LocalizedLink href="/guides/features/registry">реестр</LocalizedLink>.

::: info МИГРАЦИЯ СУЩЕСТВУЮЩЕГО ПРОЕКТА
<!-- -->
Если вы хотите перенести существующий проект в сгенерированные проекты, чтобы
улучшить процесс разработки и воспользоваться преимуществами нашего
<LocalizedLink href="/guides/features/cache">кэша</LocalizedLink>, ознакомьтесь
с
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">руководством по миграции</LocalizedLink>.
<!-- -->
:::
