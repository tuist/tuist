---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Начните {#get-started}

Проще всего начать работу с Tuist в любой директории или в директории вашего
проекта или рабочей области Xcode:

::: кодовая группа

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
:::

Команда проведет вас по шагам, чтобы
<LocalizedLink href="/guides/features/projects">создать сгенерированный
проект</LocalizedLink> или интегрировать существующий проект или рабочее
пространство Xcode. Она поможет вам подключить вашу установку к удаленному
серверу, предоставляя доступ к таким функциям, как
<LocalizedLink href="/guides/features/selective-testing">выборочное
тестирование</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">предварительные
просмотры</LocalizedLink> и
<LocalizedLink href="/guides/features/registry">реестр</LocalizedLink>.

> [Если вы хотите перенести существующий проект в генерируемые проекты, чтобы
> улучшить работу разработчиков и воспользоваться преимуществами нашего
> <LocalizedLink href="/guides/features/cache">кэша</LocalizedLink>,
> ознакомьтесь с нашим руководством
> <LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">по
> миграции</LocalizedLink>.
