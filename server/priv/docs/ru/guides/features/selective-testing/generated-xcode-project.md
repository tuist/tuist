---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Выборочное тестирование · Возможности · Руководства · Tuist",
  "description": "Запускайте только те тесты Xcode и сгенерированного проекта, которые затронуты последними изменениями, с помощью выборочного тестирования Tuist, чтобы непрерывная интеграция предоставляла обратную связь за секунды."
}
---
# Сгенерированный Xcode-проект {#generated-xcode-project}

По мере роста проекта запуск всех тестов при каждом пуше перестаёт масштабироваться. Выборочное тестирование Tuist запускает только те тесты, цели которых изменились с момента последнего успешного запуска тестов, на основе <.localized_link href="/guides/features/projects/hashing">алгоритма хеширования</.localized_link> Tuist.

Чтобы выборочно запускать тесты в вашем <.localized_link href="/guides/features/projects">сгенерированном проекте</.localized_link>, используйте команду `tuist test`. Команда <.localized_link href="/guides/features/projects/hashing">хеширует</.localized_link> ваш проект так же, как для <.localized_link href="/guides/features/cache/module-cache">кеша модулей</.localized_link>, и при успехе сохраняет хеши, чтобы определять изменения в будущих запусках. В следующих запусках `tuist test` прозрачно использует хеши для фильтрации тестов и запускает только те, которые изменились с момента последнего успешного запуска.

`tuist test` напрямую интегрируется с <.localized_link href="/guides/features/cache/module-cache">кешем модулей</.localized_link>, чтобы использовать как можно больше бинарных файлов из вашего локального или удалённого хранилища и сократить время сборки при запуске набора тестов. Сочетание выборочного тестирования с кешированием модулей может значительно уменьшить время выполнения тестов в CI.

Если ваши тесты предназначены только для симуляторов, передайте `--destination simulator`, чтобы `tuist test` использовал и скачивал только части кэшированных бинарных файлов для симулятора. См. <.localized_link href="/guides/features/cache/module-cache#destination-selection">выбор назначения</.localized_link>. Хеши выборочного тестирования одинаковы для любого значения `--destination`.

## Раздельные задачи сборки и тестирования {#separate-build-and-test-jobs}

Выборочное тестирование поддерживает раздельные задачи сборки и тестирования. Запустите `tuist test --build-only` в задаче сборки, чтобы Tuist сохранил файл `selective-testing-graph.json` рядом с продуктами, которые выдаёт сборка. Этот граф содержит хеши, необходимые для выборочного тестирования, поэтому задаче тестирования не нужно заново генерировать проект или разрешать зависимости Swift Package, чтобы определить, какие цели запускать.

Tuist записывает граф в два места во время `--build-only`:

- Внутри бандла `.xctestproducts`, если вы передаёте `-testProductsPath`.
- Рядом с каждым файлом `.xctestrun` в директории `Build/Products/` производных данных.

Закешируйте любой из этих результатов вместе со собранными продуктами и передайте тот же путь в `--without-building` в задаче тестирования. Оба варианта работают:

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

Когда Tuist не может найти этот граф рядом с входными данными (например, если задача сборки использовала обычный `xcodebuild build-for-testing` вместо `tuist test --build-only`), он возвращается к повторной генерации проекта, чтобы всё ещё вычислить затронутые цели. Для этого отката необходимо разрешить зависимости Swift Package в задаче тестирования, поэтому сначала выполните `tuist install` или кешируйте `Tuist/.build` между задачами.

Граф отражает дерево исходного кода таким, каким оно было во время сборки. Запускайте задачу тестирования на том же коммите, что и задачу сборки — если исходный код изменится между ними, хеши перестанут соответствовать источнику, и выборочное тестирование может пропустить тесты, которые на самом деле упадут на более новой версии кода.

### Какой флаг использовать? {#which-flag-should-i-use}

`.xctestrun` и `.xctestproducts` — это два разных формата вывода Xcode, и они представляют компромисс между портативностью и удобством конвейера:

- **`-testProductsPath` (`.xctestproducts`) — рекомендуется для новых конвейеров.** Это самодостаточная директория: собранные бинарные файлы `.xctest` и их файлы `.xctestrun` находятся внутри неё с путями, относительными к корню бандла, поэтому она остаётся действительной независимо от того, куда её поместят.
- **`-xctestrun` (сырой `.xctestrun`) — используйте, если у вас уже есть конвейер, построенный вокруг производных данных.** `xcodebuild build-for-testing` по умолчанию записывает `.xctestrun` в верхнюю часть `<derivedData>/Build/Products/` и указывает на тестовые бандлы, расположенные в других местах этого дерева. Повторное использование в другой задаче означает сохранение путей в `Build/Products/` неизменными.

Если вы начинаете с нуля, предпочтите `-testProductsPath`. Если вы подключаете Tuist к существующему конвейеру, который уже кеширует производные данные, `-xctestrun` обеспечит тот же быстрый путь, пока задача сборки выполняется через `tuist test --build-only`.

Любой режим ввода взаимно исключаем с `-workspace`/`-project`/`-scheme`, поэтому Tuist пропускает эти флаги, когда аргументы сквозной передачи включают `-xctestrun` или `-testProductsPath`, и передаёт выбранные цели через `-only-testing`.

> [!WARNING]
> **Гранулярность на уровне модуля против уровня файла**
>
> Из-за невозможности обнаружения зависимостей в коде между тестами и исходниками максимальная гранулярность стандартного выборочного тестирования находится на уровне цели. [Стратегия покрытия](#coverage-based-test-selection) сужает её до отдельных тестов. Поэтому мы рекомендуем держать ваши цели небольшими и сфокусированными, чтобы максимизировать преимущества выборочного тестирования.


## Выбор тестов на основе покрытия {#coverage-based-test-selection}

> [!NOTE]
> **Ранний доступ**
>
> Выбор тестов на основе покрытия находится в раннем доступе. Свяжитесь с нами, чтобы включить его для вашего аккаунта. Пока он не включён, стратегия ведёт себя как стандартное выборочное тестирование.

По умолчанию выборочное тестирование пропускает целые тестовые цели, хеш которых уже прошёл проверку. Стратегия `.coverage()` идёт дальше: в оставшихся тестовых целях она также пропускает тесты, покрытие кода которых в предыдущем запуске не включает ни одного файла, затронутого вашим изменением. Она работает с тестами XCTest и XCUITest, а также с тестами [Swift Testing](#swift-testing) в наборах, настроенных для неё. Включите её в `Tuist.swift`:

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

- **Загрузку покрытия.** Tuist выбирает тесты по покрытию, загруженному предыдущими запусками, поэтому `tuist test` не сможет загрузить манифест, в котором `.coverage()` установлено с `upload: false`.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) версии 0.5.1 или новее**, [подключённый к вашим тестовым целям](#linking-testcoverageattribution). Он записывает, какие файлы выполняет каждый тест, и пропускает тесты, которые Tuist не выбрал. Цель без него всегда пропускается целиком, как по умолчанию.
- **Полные запуски тестов, достаточно часто.** Запуск с `tuist test --no-selective-testing` выполняет каждый тест и становится базовой линией. Выборочный запуск сравнивается с недавним запуском в истории коммита на той же платформе и не применяет покрытие без такой базовой линии. Где и как часто их запускать зависит от рабочего процесса вашей команды: например, при каждом коммите в основную ветку, каждую ночь или в ветках релизов. Мы рекомендуем основную ветку: полный запуск там также выявляет то, что покрытие не видит, например фикстуры или сервисы, от которых зависит тест, до выпуска изменений.

При включённой стратегии `tuist test` пропускает цели, хеш которых уже прошёл проверку, затем спрашивает у Tuist, какие тесты из оставшихся целей может затронуть ваше изменение. Цели без затронутых тестов не собираются. Новые тесты, тесты, которые упали в прошлый раз, тесты в изменённом тестовом файле и тесты без записанного покрытия всегда запускаются.

Иногда покрытие не применяется, и в выводе объясняется почему: все тесты целей, хеш которых не прошёл проверку, запускаются, как при обычном выборочном тестировании. Это происходит, если нет недавней базовой линии на той же платформе, изменение затронуло более 5000 файлов или изменился файл, который может повлиять на любой тест, например `Package.resolved`, `Project.swift` или `.xcconfig`. Чтобы запустить все тесты, передайте `--no-selective-testing`.

> [!NOTE]
> **Покрытие тестов**
>
> Инструменты покрытия, читающие отчёт одного запуска, включая Xcode, предполагают, что был выполнен весь набор тестов, поэтому отчёт выборочного запуска исключает пропущенные тесты. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">Покрытие кода</.localized_link> Tuist вместо этого переносит покрытие пропущенных тестовых целей из предыдущего запуска, используя <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">покрытие на уровне целей</.localized_link>, которое оно записывает при каждом запуске.

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

Затем добавьте его к вашим тестовым целям, но никогда к целям приложения:

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

По умолчанию Tuist подключает пакеты как статические фреймворки. Цель только для XCTest ничего не использует из пакета, поэтому линковщик удаляет его, а вместе с ним запись данных и пропуск тестов. Либо добавьте `-ObjC` в `OTHER_LDFLAGS` тестовой цели, либо подключите пакет динамически в `Tuist/Package.swift`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

У Swift Testing нет API наблюдений, к которому могла бы подключиться библиотека, поэтому её тестам нужен трейт `.coverageAttribution` от TestCoverageAttribution в их сюите. Трейт применяется к сюитам, вложенным в ту, которая его имеет. Тесты в сюитах без него не записывают покрытие по отдельным тестам, поэтому они запускаются всякий раз, когда запускается их цель.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Тесты не должны пересекаться.** По умолчанию Swift Testing запускает тесты процесса параллельно, и счётчики покрытия не могут различить тесты, выполняющиеся одновременно, поэтому такие тесты не записывают собственное покрытие и всегда запускаются. `.serialized` упорядочивает только тесты внутри одной сюиты, поэтому этого достаточно лишь тогда, когда у цели одна сюита. Для XCTest ничего дополнительно не нужно: параллельное тестирование запускает каждый клон теста в своём процессе.
- **Отключайте параллелизацию для каждой тестовой цели.** Xcode применяет настройку к каждой тестовой цели, поэтому вы можете отключить её только для тех целей, где хотите выбирать тесты по отдельности, а остальные цели схемы продолжат работать параллельно. Отдельная схема не нужна. Установите её на тестируемой цели: `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, это также запустит XCTest-тесты этой цели без клонов. Схемы, которые генерирует Tuist, берут настройку из `testingOptions` проекта; она отключена, если только не включает `.parallelizable` или `.swiftTestingOnlyParallelizable`. Передача `-parallel-testing-enabled YES` или `NO` в `tuist test` переопределяет настройку каждой цели для этого запуска.
- **Для пропуска требуется Swift 6.3 (Xcode 26.4) или новее.** Трейт отменяет тесты, которые Tuist не выбрал, и помечает их как пропущенные. В более ранних версиях тесты всё равно записывают покрытие, но те, которые Tuist не выбрал, всё равно запускаются.

### Тесты, которые всегда запускаются {#tests-that-always-run}

Покрытие видит только код, который выполняет тест. Тест, чьи реальные входные данные — это фикстуры, ресурсы, сеть или окружение, может сломаться без изменения любого покрытого кода. Пометьте его как неудаляемый, и он будет запускаться, даже если Tuist его не выбрал:

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

Это применяется только в запускаемых тестовых целях. Цель, хеш которой уже прошёл проверку или ни один тест которой Tuist не выбрал, пропускается целиком и никогда не запускается, поэтому её неудаляемые тесты тоже не выполняются.

Смотрите [README TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) для всех опций.


## Комментарии к pull/merge-запросам {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-форжем**
>
> Чтобы получать автоматические комментарии к pull/merge-запросам, интегрируйте ваш <.localized_link href="/guides/server/accounts-and-projects">проект Tuist</.localized_link> с Git-форжем: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> или <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Как только ваш проект Tuist будет подключён к вашей Git-платформе, такой как [GitHub](https://github.com), и вы начнёте использовать `tuist test` в рамках вашего CI-процесса, Tuist опубликует комментарий прямо в ваших pull/merge-запросах, указывая, какие тесты были запущены, а какие пропущены: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Анализ промахов на панели управления {#investigating-misses-on-the-dashboard}

Когда ранее закэшированная тестовая цель отображается как промах, вкладка **Выборочное тестирование** на странице запуска тестов позволяет детально изучить входные данные, сформировавшие хеш. Развёртывание строки показывает подхеши по компонентам — исходный код, зависимости, переменные окружения, настройки проекта и целей, Info.plist, entitlements, заголовки и т. д., — чтобы вы могли точно определить входные данные, которые изменились между запусками.

Используйте кнопку **Копировать как JSON** в верхней части карточки «Выборочное тестирование», чтобы экспортировать все цели выборочного тестирования с их хешами и подхешами. Сравнение JSON между двумя запусками — самый быстрый способ подтвердить, какие входные данные изменились, когда хеш тестовой цели сместился.
