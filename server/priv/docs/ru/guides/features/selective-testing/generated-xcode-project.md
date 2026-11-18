---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Выборочное тестирование · Возможности · Руководства · Tuist",
  "description": "Запускайте только те тесты Xcode и сгенерированных проектов, которые затронуты последними изменениями, с помощью выборочного тестирования Tuist, чтобы непрерывная интеграция предоставляла обратную связь за считанные секунды."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project}

По мере роста проекта запуск всех тестов при каждом пуше перестаёт масштабироваться. Выборочное тестирование Tuist запускает только те тесты, цели которых изменились с момента последнего успешного запуска тестов, на основе <.localized_link href="/guides/features/projects/hashing">алгоритма хеширования</.localized_link> Tuist.

Чтобы запускать тесты выборочно в вашем <.localized_link href="/guides/features/projects">сгенерированном проекте</.localized_link>, используйте команду `tuist test`. Команда <.localized_link href="/guides/features/projects/hashing">хеширует</.localized_link> ваш проект так же, как и для <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link>, и в случае успеха сохраняет хеши, чтобы определить, что изменилось в будущих запусках. В последующих запусках `tuist test` прозрачно использует хеши для фильтрации тестов и запускает только те, которые изменились с момента последнего успешного прогона.

`tuist test` напрямую интегрируется с <.localized_link href="/guides/features/cache/module-cache">кэшем модулей</.localized_link>, чтобы использовать как можно больше бинарных файлов из вашего локального или удалённого хранилища и сократить время сборки при запуске набора тестов. Сочетание выборочного тестирования с кэшированием модулей может значительно сократить время выполнения тестов в вашем CI.

Если ваши тестовые прогоны ориентированы только на симуляторы, передайте `--destination simulator`, чтобы `tuist test` использовал и загружал только части для симуляторов из кэшированных бинарных файлов. См. <.localized_link href="/guides/features/cache/module-cache#destination-selection">выбор назначения</.localized_link>. Хеши для выборочного тестирования одинаковы для любого значения `--destination`.

## Раздельные задачи сборки и тестирования {#separate-build-and-test-jobs}

Выборочное тестирование поддерживает раздельные задачи сборки и тестирования. Запустите `tuist test --build-only` в задаче сборки, чтобы Tuist мог сохранить файл `selective-testing-graph.json` рядом с продуктами, созданными сборкой. Этот граф содержит хеши, необходимые для выборочного тестирования, поэтому задаче тестирования не нужно заново генерировать проект или разрешать зависимости Swift Package, чтобы определить, какие цели запускать.

Во время `--build-only` Tuist записывает граф в два места:

- Внутри бандла `.xctestproducts`, если вы передали `-testProductsPath`.
- Рядом с каждым файлом `.xctestrun` в директории `Build/Products/` производных данных.

Закэшируйте любой из этих результатов вместе со собранными продуктами и передайте тот же путь в `--without-building` в задаче тестирования. Оба варианта работают:

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

Если Tuist не может найти этот граф рядом с входными данными (например, когда задача сборки использовала обычный `xcodebuild build-for-testing` вместо `tuist test --build-only`), он переходит к повторной генерации проекта, чтобы всё ещё иметь возможность вычислить затронутые цели. Для этого резервного варианта требуется разрешение зависимостей Swift Package в задаче тестирования, поэтому сначала выполните `tuist install` или закэшируйте `Tuist/.build` между задачами.

Граф отражает дерево исходного кода таким, каким оно было во время сборки. Запускайте задачу тестирования на том же коммите, что и задачу сборки — если исходный код изменится между ними, хеши перестанут соответствовать коду, и выборочное тестирование может пропустить тесты, которые на самом деле упадут на новой версии кода.

### Какой флаг использовать? {#which-flag-should-i-use}

`.xctestrun` и `.xctestproducts` — это два разных формата вывода Xcode, и они представляют собой компромисс между портативностью и удобством конвейера:

- **`-testProductsPath` (`.xctestproducts`) — рекомендуется для новых конвейеров.** Это самодостаточная директория: собранные бинарные файлы `.xctest` и их файлы `.xctestrun` находятся внутри неё, а пути сделаны относительными корня бандла, поэтому она остаётся рабочей независимо от того, куда её поместить.
- **`-xctestrun` (сырой `.xctestrun`) — используйте, если у вас уже есть конвейер, построенный вокруг производных данных.** `xcodebuild build-for-testing` по умолчанию записывает `.xctestrun` в верхнюю часть `<derivedData>/Build/Products/` и указывает на тестовые бандлы, расположенные в других местах этого дерева. Повторное использование в другой задаче означает сохранение путей в `Build/Products/` без изменений.

Если вы начинаете с нуля, предпочтите `-testProductsPath`. Если вы интегрируете Tuist в существующий конвейер, который уже кэширует производные данные, `-xctestrun` обеспечит тот же быстрый путь, пока задача сборки выполняется через `tuist test --build-only`.

Любой из режимов ввода взаимно исключает `-workspace`/`-project`/`-scheme`, поэтому Tuist пропускает эти флаги, если сквозные аргументы включают `-xctestrun` или `-testProductsPath`, и передаёт выбранные цели через `-only-testing`.

> [!WARNING]
> **Гранулярность на уровне модуля против уровня файла**
>
> Из-за невозможности обнаружения зависимостей в коде между тестами и исходниками максимальная гранулярность стандартного выборочного тестирования находится на уровне цели. [Стратегия покрытия](#coverage-based-test-selection) сужает её до отдельных тестов. Поэтому мы рекомендуем держать ваши цели небольшими и сфокусированными, чтобы максимизировать преимущества выборочного тестирования.


## Выбор тестов на основе покрытия {#coverage-based-test-selection}

> [!NOTE]
> **Ранний доступ**
>
> Выбор тестов на основе покрытия находится в раннем доступе. Свяжитесь с нами, чтобы включить его для вашего аккаунта. Пока он не включён, стратегия ведёт себя как стандартное выборочное тестирование.

По умолчанию выборочное тестирование пропускает целые тестовые цели, хеш которых уже прошёл проверку. Стратегия `.coverage()` идёт дальше: в оставшихся тестовых целях она также пропускает тесты, чьё покрытие кода в предыдущем прогоне не включает ни одного файла, затронутого вашим изменением. Она работает с тестами XCTest и XCUITest, а также с тестами [Swift Testing](#swift-testing) в наборах, настроенных для неё. Включите её в `Tuist.swift`:

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

- **Загрузка данных о покрытии.** Tuist выбирает тесты на основе покрытия, загруженного предыдущими прогонами, поэтому `tuist test` не сможет загрузить манифест, в котором `.coverage()` установлено с `upload: false`.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) версии 0.5.1 или новее**, [подключённый к вашим тестовым целям](#linking-testcoverageattribution). Он записывает, какие файлы выполняет каждый тест, и пропускает тесты, которые Tuist не выбрал. Цель без него будет пропускаться только целиком, как в стандартном режиме.
- **Полные прогоны тестов, достаточно часто.** Прогон с `tuist test --no-selective-testing` выполняет все тесты и становится базовой линией. Выборочный прогон сравнивается с недавним прогоном в истории того же коммита на той же платформе и не применяет покрытие без такой базы. Где и как часто их запускать, зависит от процессов вашей команды: например, на каждый коммит в основной ветке, каждую ночь или в релизных ветках. Мы рекомендуем основную ветку: полный прогон там также выявляет то, что покрытие не видит, например, фикстуры или сервисы, от которых зависит тест, до выпуска изменения.

При включённой стратегии `tuist test` пропускает цели, хеш которых уже прошёл проверку, затем спрашивает у Tuist, какие тесты из оставшихся целей могут быть затронуты вашим изменением. Цели без затронутых тестов не собираются. Новые тесты, тесты, упавшие в последний раз, тесты в изменённом тестовом файле и тесты без записанного покрытия всегда запускаются.

Иногда покрытие не применяется, и в выводе указывается причина: все тесты целей, хеш которых не прошёл проверку, запускаются, как при стандартном выборочном тестировании. Это происходит, если нет недавней базовой линии на той же платформе, если изменение затрагивает более 5000 файлов или если изменился файл, способный повлиять на любой тест, например `Package.resolved`, `Project.swift` или `.xcconfig`. Чтобы запустить все тесты, передайте `--no-selective-testing`.

> [!NOTE]
> **Покрытие кода тестами**
>
> Инструменты покрытия, читающие отчёт одного прогона, включая Xcode, предполагают, что был запущен весь набор тестов, поэтому отчёт выборочного прогона исключает пропущенные тесты. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">Покрытие кода</.localized_link> Tuist вместо этого переносит данные о покрытии пропущенных тестовых целей из предыдущего прогона, используя <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">покрытие на уровне целей</.localized_link>, которое записывается при каждом прогоне.

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

Затем добавьте его к вашим тестовым целям, но никогда — к целям приложения:

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

По умолчанию Tuist подключает пакеты как статические фреймворки. Цель, использующая только XCTest, не ссылается ни на что из пакета, поэтому компоновщик удаляет его, а вместе с ним и запись данных, и пропуск тестов. Либо добавьте `-ObjC` в `OTHER_LDFLAGS` тестовой цели, либо подключите пакет динамически в `Tuist/Package.swift`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

У Swift Testing нет API наблюдения, к которому могла бы подключиться библиотека, поэтому её тестам нужен трейт `.coverageAttribution` от TestCoverageAttribution в их сюите. Трейт применяется также к вложенным сюитам. Тесты в сюитах без него не записывают покрытие по отдельным тестам, поэтому они запускаются каждый раз, когда запускается их цель.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Тесты не должны перекрываться.** По умолчанию Swift Testing запускает тесты процесса параллельно, а счётчики покрытия не могут различить тесты, выполняющиеся одновременно, поэтому такие тесты не записывают собственное покрытие и всегда запускаются. `.serialized` упорядочивает только тесты внутри одной сюиты, поэтому этого достаточно, только если в цели одна сюита. Для XCTest ничего дополнительно не требуется: при параллельном тестировании каждый клон теста выполняется в своём процессе.
- **Отключайте параллелизацию для каждой тестовой цели.** Xcode применяет настройку к каждой тестовой цели, поэтому вы можете отключить её только для тех целей, где хотите выбирать тесты по отдельности, а остальные цели схемы продолжат работать параллельно. Отдельная схема не нужна. Установите это на тестируемой цели: `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, что также запустит XCTest-тесты этой цели без клонов. Схемы, генерируемые Tuist, берут эту настройку из `testingOptions` проекта; она отключена, если только не включает `.parallelizable` или `.swiftTestingOnlyParallelizable`. Передача `-parallel-testing-enabled YES` или `NO` в `tuist test` переопределяет настройку каждой цели для этого прогона.
- **Для пропуска тестов требуется Swift 6.3 (Xcode 26.4) или новее.** Трейт отменяет тесты, которые Tuist не выбрал, и отмечает их как пропущенные. В более ранних версиях тесты всё равно записывают покрытие, но те, которые Tuist не выбрал, всё равно запускаются.

### Тесты, которые всегда запускаются {#tests-that-always-run}

Покрытие видит только код, который выполняет тест. Тест, чьи реальные входные данные — это фикстуры, ресурсы, сеть или окружение, может сломаться без изменения какого-либо покрытого кода. Пометьте его как неотключаемый, и он будет запускаться, даже если Tuist его не выбрал:

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

Это применяется только в запускаемых тестовых целях. Цель, хеш которой уже прошёл проверку или ни один тест которой не был выбран Tuist, пропускается целиком и никогда не запускается, поэтому её неотключаемые тесты тоже не выполняются.

Смотрите все варианты в [README TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution#unskippable-tests).

### Просмотр выбора {#inspecting-a-selection}

Вкладка «Выборочное тестирование» в отчёте о прогоне показывает, какие тесты были выбраны по покрытию и почему. Те же данные доступны через CLI с флагом `--json` для скриптов и агентам через <.localized_link href="/guides/features/agentic-coding/mcp">сервер Model Context Protocol</.localized_link>:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

Когда покрытие не применяется, тесты всё равно считаются выбранными на основе покрытия: причина указывает, почему покрытие не смогло принять решение, например `tracked_file_changed`.


## Комментарии к пул-/мердж-реквестам {#pullmerge-request-comments}

> [!WARNING]
> **Требуется интеграция с Git-форжем**
>
> Чтобы получать автоматические комментарии к пул-/мердж-реквестам, интегрируйте свой <.localized_link href="/guides/server/accounts-and-projects">проект Tuist</.localized_link> с Git-форжем: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> или <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Как только ваш проект Tuist будет подключён к вашей Git-платформе, такой как [GitHub](https://github.com), и вы начнёте использовать `tuist test` в рамках вашего CI-процесса, Tuist опубликует комментарий прямо в ваших пул-/мердж-реквестах, указав, какие тесты были запущены, а какие пропущены: ![Комментарий приложения GitHub со ссылкой на Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Анализ промахов на дашборде {#investigating-misses-on-the-dashboard}

Когда ранее закэшированная тестовая цель отображается как промах, вкладка **Выборочное тестирование** на странице прогона позволяет детально изучить входные данные, сформировавшие хеш. Развёртывание строки показывает подхеши по компонентам — исходники, зависимости, переменные окружения, настройки проекта и цели, Info.plist, entitlements, заголовки и т. д., — чтобы вы могли точно определить входные данные, изменившиеся между прогонами.

Используйте кнопку **Копировать как JSON** в верхней части карточки «Выборочное тестирование», чтобы экспортировать все цели выборочного тестирования с их хешами и подхешами. Сравнение JSON двух прогонов — самый быстрый способ подтвердить, какие входные данные изменились, когда хеш тестовой цели drifted.
