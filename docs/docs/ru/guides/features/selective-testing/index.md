---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# Выборочное тестирование {#selective-testing}

::: warning ТРЕБОВАНИЯ
<!-- -->
- Проект, созданный
  <LocalizedLink href="/guides/features/projects"></LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
<!-- -->
:::

Чтобы выборочно запускать тесты с помощью сгенерированного проекта, используйте
команду `tuist test`. Команда
<LocalizedLink href="/guides/features/projects/hashing">хеширует</LocalizedLink>
ваш проект Xcode так же, как и при
<LocalizedLink href="/guides/features/cache#cache-warming">прогревании
кэша</LocalizedLink>, и в случае успеха сохраняет хэши, чтобы определить, что
изменилось в будущих запусках.

В будущих запусках `tuist test` прозрачно использует хэши для фильтрации тестов,
чтобы запускать только те, которые изменились с момента последнего успешного
запуска тестов.

Например, предположим, что имеется следующий граф зависимостей:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` имеет тесты `FeatureBTests` и зависит от `Core`
- `Core` имеет тесты `CoreTests`

`tuist test` будет вести себя следующим образом:

| Действие                | Описание                                                         | Внутреннее состояние                                             |
| ----------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------- |
| `tuist test` invocation | Запускает тесты в `CoreTests`, `FeatureATests` и `FeatureBTests` | Хеши `FeatureATests`, `FeatureBTests` и `CoreTests` сохраняются. |
| `Особенность` обновлен  | Разработчик изменяет код целевого объекта.                       | Как и раньше                                                     |
| `tuist test` invocation | Запускает тесты в `FeatureATests`, поскольку хеш изменился.      | Новый хеш `FeatureATests` сохраняется.                           |
| `Обновлен ядро`         | Разработчик изменяет код целевого объекта.                       | Как и раньше                                                     |
| `tuist test` invocation | Запускает тесты в `CoreTests`, `FeatureATests` и `FeatureBTests` | Хеши `FeatureATests`, `FeatureBTests` и `CoreTests` сохраняются. |

`tuist test` напрямую интегрируется с кэшированием бинарных файлов, чтобы
использовать как можно больше бинарных файлов из локального или удаленного
хранилища для сокращения времени сборки при запуске набора тестов. Сочетание
выборочного тестирования с кэшированием бинарных файлов может значительно
сократить время, необходимое для запуска тестов в вашей CI.

## Тесты пользовательского интерфейса {#ui-tests}

Tuist поддерживает выборочное тестирование UI-тестов. Однако Tuist необходимо
заранее знать место назначения. Только если вы укажете параметр `destination`,
Tuist будет выборочно запускать UI-тесты, например:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
