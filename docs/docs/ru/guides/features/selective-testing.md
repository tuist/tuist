---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Выборочное тестирование {#selective-testing}

По мере роста вашего проекта растет и количество тестов. В течение длительного
времени запуск всех тестов при каждом PR или push в `main` занимает десятки
секунд. Но это решение не подходит для тысяч тестов, которые может иметь ваша
команда.

При каждом запуске теста на CI вы, скорее всего, повторно запускаете все тесты,
независимо от изменений. Селективное тестирование Tuist помогает значительно
ускорить выполнение тестов, запуская только те тесты, которые изменились с
момента последнего успешного запуска теста на основе нашего
<LocalizedLink href="/guides/features/projects/hashing">алгоритма
хеширования</LocalizedLink>.

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Из-за невозможности обнаружить зависимости между тестами и источниками в коде
максимальная детальность выборочного тестирования достигается на уровне целей.
Поэтому мы рекомендуем делать цели небольшими и сфокусированными, чтобы
максимально использовать преимущества выборочного тестирования.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Инструменты тестового покрытия предполагают, что весь набор тестов запускается
сразу, что делает их несовместимыми с выборочным запуском тестов — это означает,
что данные покрытия могут не отражать реальность при использовании выбора
тестов. Это известное ограничение, и оно не означает, что вы делаете что-то не
так. Мы рекомендуем командам подумать о том, приносит ли покрытие в этом
контексте значимую информацию, и если да, то будьте уверены, что мы уже думаем о
том, как сделать так, чтобы покрытие работало правильно с выборочным запуском в
будущем.
<!-- -->
:::


## Комментарии к pull/merge request {#pullmerge-request-comments}

::: warning ТРЕБУЕТСЯ ИНТЕГРАЦИЯ С GIT
<!-- -->
Чтобы получить автоматические комментарии к запросам pull/merge, интегрируйте
ваш
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist-проект</LocalizedLink>
с
<LocalizedLink href="/guides/server/authentication">Git-платформой</LocalizedLink>.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
