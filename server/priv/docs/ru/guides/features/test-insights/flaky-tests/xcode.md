---
{
  "title": "Нестабильные тесты в Xcode",
  "titleTemplate": ":title · Нестабильные тесты · Аналитика тестов · Возможности · Руководства · Tuist",
  "description": "Обнаруживайте, управляйте и изолируйте нестабильные тесты в проектах Xcode с помощью Tuist."
}
---
# Нестабильные тесты Xcode {#xcode-flaky-tests}

> [!IMPORTANT]
> **Требования**
>
> - Настроены <.localized_link href="/guides/features/test-insights/xcode">инсайты тестов Xcode</.localized_link>. Tuist определяет нестабильные тесты по событиям инсайтов, загружаемым каждым запуском тестов.

<!-- @snippet: ./_intro -->

![Страница нестабильных тестов](/images/guides/features/test-insights/flaky-tests-page.png)

## Как работает обнаружение нестабильных тестов {#how-it-works}

Tuist обнаруживает нестабильные тесты двумя способами:

### Повторные попытки тестов {#test-retries}

Когда вы запускаете тесты с функцией повторных попыток, Tuist анализирует результаты каждой попытки. Если тест падает в некоторых попытках, но проходит в других, он помечается как нестабильный.

Передайте `-retry-tests-on-failure` или `-test-iterations` через `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Детали нестабильного тест-кейса](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Карантин для нестабильных тестов {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Тест в карантине может находиться в одном из двух режимов:

- **Игнорирование сбоев**: тест продолжает выполняться, но `tuist xcodebuild test` скрывает сбои. Сбои всё ещё поступают в детектор нестабильных тестов, поэтому вы можете продолжать наблюдать за тестом, не ломая сборку. Выберите этот режим для теста, который вы активно исследуете.
- **Пропуск**: xcodebuild получает `-skip-testing <identifier>`, поэтому тест никогда не запускается. Он не создаёт новых результатов и исчезает с панели нестабильных тестов, пока вы не включите его снова. Выберите этот режим, когда тест сломан, медленный или настолько постоянно нестабилен, что его запуск просто тратит минуты CI впустую.

<!-- @snippet: ./_quarantined-passing -->

### Запуск тестов {#running-tests}

`tuist xcodebuild test` — это обёртка-пасsthrough, которая автоматически поддерживает оба режима. Используйте её так же, как вызывали бы xcodebuild:

```sh
tuist xcodebuild test -scheme MyScheme
```

Пропущенные тесты добавляются к вашему вызову xcodebuild как `-skip-testing <identifier>` и никогда не запускаются. Тесты с игнорированием сбоев выполняются нормально; если они падают, сбой маскируется в итоговом статусе сборки.

#### Обход карантина {#bypassing-quarantine}

`tuist xcodebuild test` принимает `--skip-quarantine` для запуска всего, включая тесты с игнорированием сбоев и пропущенные тесты:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### Прямой вызов xcodebuild {#calling-xcodebuild-directly}

Если вы не можете использовать `tuist xcodebuild test`, самостоятельно разверните тесты в карантине в аргументы `-skip-testing` с помощью `tuist test case list`:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

Это безопасное поведение по умолчанию вне `tuist xcodebuild test`: маскировка сбоев для тестов с игнорированием происходит только при использовании этой команды, поэтому пропуск обоих режимов позволяет избежать ложных сбоев CI. Если вам нужен более тонкий контроль, используйте вместо этого `tuist xcodebuild test`.

## Стресс-тестирование новых тестов {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Тест-кейс считается новым, если он не запускался в CI за последние 90 дней на ветке проекта по умолчанию или на коммите, который затем попал в эту ветку. При использовании очереди слияния тест-кейс, запущенный очередью, становится известным после попадания коммита очереди, и остаётся новым, если очередь его отбрасывает. Коммиты сопоставляются через <.localized_link href="/guides/features/test-insights/xcode#git-history">историю Git</.localized_link>, которую Tuist собирает в CI.

<!-- @snippet: ./_stress-modes -->

Передайте его перед аргументами пасsthrough или установите `TUIST_TEST_STRESS_NEW_TESTS`, чтобы менять режим для каждого этапа CI:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

Повторные запуски повторно используют то, что было собрано при первом проходе.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
