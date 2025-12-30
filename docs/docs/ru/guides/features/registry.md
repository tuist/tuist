---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Реестр {#registry}

С ростом числа зависимостей увеличивается и время на их устранение. В то время
как другие менеджеры пакетов, такие как [CocoaPods](https://cocoapods.org/) или
[npm](https://www.npmjs.com/), являются централизованными, менеджер пакетов
Swift таковым не является. Из-за этого SwiftPM приходится разрешать зависимости
путем глубокого клонирования каждого репозитория, что может занимать больше
времени и памяти, чем при централизованном подходе. Чтобы решить эту проблему,
Tuist предоставляет реализацию [Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md),
чтобы вы могли загружать только те коммиты, которые вам _действительно нужны_.
Пакеты в реестре основаны на [Swift Package
Index](https://swiftpackageindex.com/) - если вы можете найти пакет там, то он
также доступен в реестре Tuist. Кроме того, пакеты распределены по всему миру с
использованием пограничного хранилища для минимальной задержки при их
разрешении.

## Использование {#usage}

Чтобы настроить реестр, выполните следующую команду в каталоге вашего проекта:

```bash
tuist registry setup
```

Эта команда генерирует файл конфигурации реестра, который включает реестр для
вашего проекта. Убедитесь, что этот файл зафиксирован, чтобы ваша команда также
могла воспользоваться преимуществами реестра.

### Аутентификация (необязательно) {#authentication}

Аутентификация **является необязательной**. Без аутентификации вы можете
использовать реестр с ограничением скорости **1 000 запросов в минуту** на один
IP-адрес. Чтобы получить более высокий предел скорости **20 000 запросов в
минуту**, можно пройти аутентификацию, выполнив команду:

```bash
tuist registry login
```

::: info
<!-- -->
Для аутентификации требуется учетная запись
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist и проект</LocalizedLink>.
<!-- -->
:::

### Разрешение зависимостей {#resolving-dependencies}

Чтобы разрешить зависимости из реестра, а не из контроля исходных текстов,
продолжайте читать в зависимости от настроек вашего проекта:
- <LocalizedLink href="/guides/features/registry/xcode-project">Проект Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Сгенерированный проект с интеграцией пакета Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Сгенерированный проект с интеграцией пакетов на основе XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Пакет Swift</LocalizedLink>

Чтобы настроить реестр в CI, следуйте этому руководству:
<LocalizedLink href="/guides/features/registry/continuous-integration">Непрерывная интеграция</LocalizedLink>.

### Идентификаторы реестра пакетов {#package-registry-identifiers}

При использовании идентификаторов реестра пакетов в файле `Package.swift` или
`Project.swift` необходимо преобразовать URL-адрес пакета к соглашению реестра.
Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например,
чтобы использовать реестр для пакета
`https://github.com/pointfreeco/swift-composable-architecture`, идентификатор
реестра пакета будет `pointfreeco.swift-composable-architecture`.

::: info
<!-- -->
Идентификатор не может содержать более одной точки. Если имя репозитория
содержит точку, она заменяется знаком подчеркивания. Например, пакет
`https://github.com/groue/GRDB.swift` будет иметь идентификатор реестра
`groue.GRDB_swift`.
<!-- -->
:::
