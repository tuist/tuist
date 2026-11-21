---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Выборочное тестирование · Возможности · Руководства · Tuist",
  "description": "Запускайте только те тесты в Xcode и сгенерированных проектах, которые затронуты последними изменениями, с помощью выборочного тестирования Tuist, чтобы непрерывная интеграция предоставляла обратную связь за считанные секунды."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project}

По мере роста проекта запуск всех тестов при каждом пуше перестаёт масштабироваться. Выборочное тестирование Tuist запускает только те тесты, цели которых изменились с момента последнего успешного запуска тестов, на основе <.localized_link href="/guides/features/projects/hashing">алгоритма хеширования</.localized_link> Tuist.

Чтобы выборочно запускать тесты в вашем <.localized_link href="/guides/features/projects">сгенерированном проекте</.localized_link>, используйте команду `tuist test`. Команда <.localized_link href="/guides/features/projects/hashing">хеширует</.localized_link> ваш проект так же, как и для <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link>, и в случае успеха сохраняет хеши, чтобы определить, что изменилось в будущих запусках. В следующих запусках `tuist test` прозрачно использует хеши для фильтрации тестов и запускает только те, которые изменились с момента последнего успешного прогона.

`tuist test` напрямую интегрируется с <.localized_link href="/guides/features/cache/module-cache">кэшем модулей</.localized_link>, чтобы использовать как можно больше бинарных файлов из вашего локального или удалённого хранилища и сократить время сборки при запуске набора тестов. Сочетание выборочного тестирования с кэшированием модулей может значительно сократить время выполнения тестов в вашем CI.

Если ваши тесты запускаются только на симуляторах, передайте флаг `--destination simulator`, чтобы `tuist test` использовал и скачивал только части для симуляторов из кэшированных бинарных файлов. См. раздел <.localized_link href="/guides/features/cache/module-cache#destination-selection">выбор назначения</.localized_link>. Хеши для выборочного тестирования одинаковы для любого значения `--destination`.

## Раздельные задачи сборки и тестирования {#separate-build-and-test-jobs}

Выборочное тестирование поддерживает раздельные задачи сборки и тестирования. Запустите `tuist test --build-only` в задаче сборки, чтобы Tuist мог сохранить файл `selective-testing-graph.json` рядом с продуктами, создаваемыми сборкой. Этот граф содержит хеши, необходимые для выборочного тестирования, поэтому задаче тестирования не нужно заново генерировать проект или разрешать зависимости Swift Package, чтобы определить, какие цели запускать.

Во время выполнения `--build-only` Tuist записывает граф в два места:

- Внутри пакета `.xctestproducts`, если вы передали флаг `-testProductsPath`.
- Рядом с каждым файлом `.xctestrun` в директории `Build/Products/` производных данных.

Кэшируйте любой из этих результатов вместе со собранными продуктами и передайте тот же путь в `--without-building` в задаче тестирования. Оба варианта работают:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Если Tuist не может найти этот граф рядом с входными данными (например, когда задача сборки использовала обычный `xcodebuild build-for-testing` вместо `tuist test --build-only`), он возвращается к повторной генерации проекта, чтобы всё ещё вычислить затронутые цели. Для этого fallback-режима требуется разрешение зависимостей Swift Package в задаче тестирования, поэтому сначала выполните `tuist install` или кэшируйте `Tuist/.build` между задачами.

Граф отражает дерево исходного кода таким, каким оно было во время сборки. Запускайте задачу тестирования для того же коммита, что и задача сборки — если исходный код изменится между ними, хеши перестанут соответствовать источнику, и выборочное тестирование может пропустить тесты, которые на самом деле упадут на новой версии кода.

### Какой флаг использовать? {#which-flag-should-i-use}

`.xctestrun` и `.xctestproducts` — это два разных формата вывода Xcode, и они представляют собой компромисс между портативностью и удобством конвейера:

- **`-testProductsPath` (`.xctestproducts`) — рекомендуется для новых конвейеров.** Это самодостаточная директория: собранные бинарные файлы `.xctest` и их файлы `.xctestrun` находятся внутри неё, а пути сделаны относительными корня пакета, поэтому он остаётся действительным независимо от того, куда его поместят.
- **`-xctestrun` (сырой `.xctestrun`) — используйте, если у вас уже есть конвейер, построенный вокруг производных данных.** По умолчанию `xcodebuild build-for-testing` записывает `.xctestrun` в начало `<derivedData>/Build/Products/` и указывает на тестовые пакеты, расположенные в других местах этого дерева. Повторное использование в другой задаче означает сохранение путей в `Build/Products/` без изменений.

Если вы начинаете с нуля, предпочтите `-testProductsPath`. Если вы внедряете Tuist в существующий конвейер, который уже кэширует производные данные, `-xctestrun` обеспечит тот же быстрый путь, пока задача сборки выполняется через `tuist test --build-only`.

Любой режим ввода взаимно исключает использование `-workspace`/`-project`/`-scheme`, поэтому Tuist пропускает эти флаги, если сквозные аргументы включают `-xctestrun` или `-testProductsPath`, и передаёт выбранные цели через `-only-testing`.

> [!WARNING]
> **Гранулярность на уровне модулей против уровня файлов**
>
> Из-за невозможности обнаружения зависимостей в коде между тестами и исходниками максимальная гранулярность стандартного выборочного тестирования находится на уровне целей. [Стратегия покрытия](#coverage-based-test-selection) сужает её до отдельных тестов. Поэтому мы рекомендуем держать ваши цели небольшими и сфокусированными, чтобы максимизировать преимущества выборочного тестирования.


## Выбор тестов на основе покрытия {#coverage-based-test-selection}

> [!NOTE]
> **Ранний доступ**
>
> Выбор тестов на основе покрытия находится в раннем доступе. Свяжитесь с нами, чтобы включить его для вашего аккаунта. Пока он не включён, стратегия ведёт себя как стандартное выборочное тестирование.

По умолчанию выборочное тестирование пропускает целые тестовые цели, хеш которых уже прошёл проверку. Стратегия `.coverage()` идёт дальше: в оставшихся тестовых целях она также пропускает тесты, покрытие кода которых в предыдущем запуске не включало ни одного файла, затронутого вашим изменением. Она работает с тестами XCTest и XCUITest, а также с тестами [Swift Testing](#swift-testing) в наборах, настроенных для этого. Включите её в `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

Стратегия требует:

- **Загрузка данных покрытия.** Tuist выбирает тесты на основе покрытия, загруженного предыдущими запусками, поэтому `tuist test` не сможет загрузить манифест, в котором `.coverage()` установлено с `upload: false`.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) версии 0.5.1 или новее**, [подключённый вашими тестовыми целями](#linking-testcoverageattribution). Он записывает, какие файлы выполняет каждый тест, и пропускает тесты, которые Tuist не выбрал. Цель без него пропускается только целиком, как по умолчанию.
- **Полные запуски тестов достаточно часто.** Запуск с `tuist test --no-selective-testing` выполняет каждый тест и становится базовой линией. Выборочный запуск сравнивается с недавним запуском в истории того же коммита на той же платформе и не применяет покрытие без такой базы. Где и как часто их запускать зависит от процессов вашей команды: например, при каждом коммите в основную ветку, каждую ночь или в релизных ветках. Мы рекомендуем основную ветку: полный запуск там также выявляет до выпуска изменений то, что покрытие не видит, например, фикстуры или сервисы, от которых зависит тест.

При включённой стратегии `tuist test` пропускает цели, хеш которых уже прошёл проверку, затем запрашивает у Tuist, какие тесты оставшихся целей могут быть затронуты вашим изменением. Цели без затронутых тестов не собираются. Новые тесты, тесты, упавшие в последний раз, тесты в изменённом тестовом файле и тесты без записанного покрытия всегда запускаются.

Иногда покрытие не применяется, и в выводе указывается причина: запускаются все тесты целей, хеш которых не прошёл проверку, как при обычном выборочном тестировании. Это происходит, если нет недавней базовой линии на той же платформе, когда изменение затрагивает более 5000 файлов или когда изменился файл, способный повлиять на любой тест, например `Package.resolved`, `Project.swift` или `.xcconfig`. Чтобы запустить все тесты, передайте флаг `--no-selective-testing`.

> [!NOTE]
> **Покрытие кода тестами**
>
> Инструменты покрытия, читающие отчёт одного запуска (включая Xcode), предполагают, что был выполнен весь набор тестов, поэтому отчёт выборочного запуска исключает пропущенные тесты. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">Покрытие кода</.localized_link> Tuist вместо этого переносит данные покрытия пропущенных тестовых целей из предыдущего запуска, используя <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">покрытие на уровне целей</.localized_link>, которое записывается при каждом запуске.

### Подключение TestCoverageAttribution {#linking-testcoverageattribution}

Добавьте пакет в `Tuist/Package.swift`, закрепив его по минорной версии, так как минорный релиз 0.x может изменить то, что он записывает:

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

Затем добавьте его в ваши тестовые цели, но никогда — в цели приложения:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

По умолчанию Tuist подключает пакеты как статические фреймворки. Цель, использующая только XCTest, не ссылается ни на что из пакета, поэтому линковщик удаляет его, а вместе с ним и механизмы записи и пропуска. Либо добавьте `-ObjC` в `OTHER_LDFLAGS` тестовой цели, либо подключите пакет динамически в `Tuist/Package.swift`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

У Swift Testing нет API наблюдения, к которому могла бы подключиться библиотека, поэтому её тестам требуется трейт `.coverageAttribution` TestCoverageAttribution в их наборе (suite). Трейт применяется также к вложенным наборам. Тесты в наборах без него не записывают покрытие по отдельным тестам, поэтому они запускаются каждый раз при запуске их цели.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Тесты не должны пересекаться.** По умолчанию Swift Testing запускает тесты процесса параллельно, а счётчики покрытия не могут различить тесты, выполняющиеся одновременно, поэтому такие тесты не записывают собственное покрытие и всегда запускаются. `.serialized` упорядочивает только тесты внутри одного набора, поэтому этого достаточно лишь тогда, когда цель содержит один набор. Для XCTest ничего дополнительно не требуется: при параллельном тестировании каждый клон теста выполняется в своём процессе.
- **Отключайте параллелизацию для каждой тестовой цели.** Xcode применяет настройку к каждой тестовой цели, поэтому вы можете отключить её только для тех целей, где хотите выбирать тесты по отдельности, а остальные цели схемы продолжат работать параллельно. Отдельная схема не нужна. Установите это на тестируемой цели: `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, что также позволяет запускать XCTest-тесты этой цели без клонов. Схемы, генерируемые Tuist, берут эту настройку из `testingOptions` проекта; по умолчанию она отключена, если не указаны `.parallelizable` или `.swiftTestingOnlyParallelizable`. Передача `-parallel-testing-enabled YES` или `NO` в `tuist test` переопределяет настройку каждой цели для данного запуска.
- **Для пропуска требуется Swift 6.3 (Xcode 26.4) или новее.** Трейт отменяет тесты, которые Tuist не выбрал, и помечает их как пропущенные. В более ранних версиях тесты всё ещё записывают покрытие, но те, что Tuist не выбрал, всё равно запускаются.

### Тесты, которые всегда запускаются {#tests-that-always-run}

Покрытие видит только код, который выполняет тест. Тест, чьи реальные входные данные — это фикстуры, ресурсы, сеть или окружение, может сломаться без изменения покрытого кода. Пометьте его как неудаляемый из выбора (unskippable), и он будет запускаться, даже если Tuist его не выбрал:

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

Это применяется только в запускаемых тестовых целях. Цель, хеш которой уже прошёл проверку или ни один тест которой не был выбран Tuist, пропускается целиком и никогда не запускается, поэтому её неудаляемые тесты также не выполняются.

Смотрите [README TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) для всех вариантов.

### Просмотр выбранного {#inspecting-a-selection}

Вкладка «Выборочное тестирование» на странице запуска тестов показывает, какие тесты были выбраны покрытием и почему. Те же данные доступны через CLI с флагом `--json` для скриптов и агентам через <.localized_link href="/guides/features/agentic-coding/mcp">сервер Model Context Protocol</.localized_link>:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

Когда покрытие не применяется, тесты всё равно считаются частью выбора на основе покрытия: причина указывает, почему покрытие не смогло принять решение, например `tracked_file_changed`.


## Комментарии к pull/merge-запросам {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-форжем**
>
> Чтобы получать автоматические комментарии к pull/merge-запросам, интегрируйте ваш <.localized_link href="/guides/server/accounts-and-projects">проект Tuist</.localized_link> с Git-форжем: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> или <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Как только ваш проект Tuist будет подключён к вашей Git-платформе, такой как [GitHub](https://github.com), и вы начнёте использовать `tuist test` в рамках вашего CI-процесса, Tuist опубликует комментарий прямо в ваших pull/merge-запросах, указав, какие тесты были запущены, а какие пропущены: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Исследование промахов на дашборде {#investigating-misses-on-the-dashboard}

Когда ранее закэшированная тестовая цель отображается как промах, вкладка **Выборочное тестирование** на странице запуска тестов позволяет детально изучить входные данные, сформировавшие хеш. Раскрытие строки показывает подхеши по компонентам — исходный код, зависимости, переменные окружения, настройки проекта и цели, Info.plist, entitlements, заголовки и т. д., — чтобы вы могли точно определить входные данные, которые изменились между запусками.

Используйте кнопку **Копировать как JSON** в верхней части карточки «Выборочное тестирование», чтобы экспортировать все цели выборочного тестирования с их хешами и подхешами. Сравнение JSON между двумя запусками — самый быстрый способ подтвердить, какие входные данные изменились, когда хеш тестовой цели drifted.
