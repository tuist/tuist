---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Реестр {#registry}

> [!ВАЖНЫЕ] ТРЕБОВАНИЯ
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет
>   и проект</LocalizedLink>

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

Чтобы настроить реестр и войти в него, выполните следующую команду в каталоге
вашего проекта:

```bash
tuist registry setup
```

Эта команда генерирует файлы конфигурации реестра и регистрирует вас в реестре.
Чтобы остальные члены вашей команды могли получить доступ к реестру, убедитесь,
что сгенерированные файлы зафиксированы и что члены вашей команды выполняют
следующую команду для входа в систему:

```bash
tuist registry login
```

Теперь вы можете получить доступ к реестру! Чтобы разрешить зависимости из
реестра, а не из системы управления исходным кодом, продолжайте читать в
зависимости от настроек вашего проекта:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  project</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Сгенерированный
  проект с интеграцией пакета Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Сгенерированный
  проект с интеграцией пакетов на основе XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Пакет
  Swift</LocalizedLink>

Чтобы настроить реестр в CI, следуйте этому руководству:
<LocalizedLink href="/guides/features/registry/continuous-integration">Непрерывная
интеграция</LocalizedLink>.

### Идентификаторы реестра пакетов {#package-registry-identifiers}

При использовании идентификаторов реестра пакетов в файле `Package.swift` или
`Project.swift` необходимо преобразовать URL-адрес пакета к соглашению реестра.
Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например,
чтобы использовать реестр для пакета
`https://github.com/pointfreeco/swift-composable-architecture`, идентификатор
реестра пакета будет `pointfreeco.swift-composable-architecture`.

> [!ПРИМЕЧАНИЕ] Идентификатор не может содержать более одной точки. Если имя
> репозитория содержит точку, она заменяется знаком подчеркивания. Например,
> пакет `https://github.com/groue/GRDB.swift` будет иметь идентификатор реестра
> `groue.GRDB_swift`.
