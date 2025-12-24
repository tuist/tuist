---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA в настоящее время находится в стадии раннего предварительного
просмотра. Зарегистрируйтесь на [tuist.dev/qa](https://tuist.dev/qa), чтобы
получить доступ.
<!-- -->
:::

Качественная разработка мобильных приложений основывается на всестороннем
тестировании, но традиционные подходы имеют свои ограничения. Модульные тесты
быстры и экономически эффективны, однако они не учитывают реальные сценарии
работы пользователей. Приемочное тестирование и ручной контроль качества могут
устранить эти пробелы, но они требуют больших ресурсов и плохо масштабируются.

QA-агент Tuist решает эту задачу, имитируя подлинное поведение пользователя. Он
автономно исследует ваше приложение, распознает элементы интерфейса, выполняет
реалистичные взаимодействия и отмечает потенциальные проблемы. Такой подход
помогает выявить ошибки и проблемы юзабилити на ранних этапах разработки,
избегая при этом накладных расходов и бремени обслуживания, связанных с обычным
приемочным и QA-тестированием.

## Необходимые условия {#prerequisites}

Чтобы начать использовать Tuist QA, вам необходимо:
- Настройте загрузку
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> из
  рабочего процесса PR CI, который агент может использовать для тестирования
- <LocalizedLink href="/guides/integrations/gitforge/github">Интеграция</LocalizedLink>
  с GitHub, чтобы вы могли запускать агента прямо из вашего PR.

## Использование {#usage}

В настоящее время Tuist QA запускается непосредственно из PR. Как только у вас
есть предварительный просмотр, связанный с вашим PR, вы можете запустить
QA-агента, прокомментировав `/qa test Я хочу протестировать функцию A` на PR:

![Комментарий к триггеру QA](/images/guides/features/qa/qa-trigger-comment.png)

Комментарий содержит ссылку на сеанс прямой трансляции, где вы можете в реальном
времени наблюдать за ходом работы QA-агента и обнаруженными им проблемами. Как
только агент завершит свою работу, он опубликует сводку результатов в PR:

![Резюме теста QA](/images/guides/features/qa/qa-test-summary.png)

В отчете на панели управления, на который ссылается PR-комментарий, вы получите
список проблем и временную шкалу, чтобы вы могли проследить, как именно возникла
проблема:

![Хронология QA](/images/guides/features/qa/qa-timeline.png)

Вы можете увидеть все QA-прогоны, которые мы выполняем для нашего
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS-приложения</LocalizedLink>,
на нашей публичной панели: https://tuist.dev/tuist/tuist/qa.

::: info
<!-- -->
QA-агент работает автономно и не может быть прерван дополнительными подсказками
после запуска. Мы предоставляем подробные журналы в течение всего процесса
выполнения, чтобы помочь вам понять, как агент взаимодействовал с вашим
приложением. Эти журналы полезны для итераций контекста вашего приложения и
тестирования подсказок, чтобы лучше направлять поведение агента. Если у вас есть
отзывы о работе агента с вашим приложением, сообщите нам об этом через [GitHub
Issues](https://github.com/tuist/tuist/issues), наше сообщество
[Slack](https://slack.tuist.dev) или форум [Community
Forum](https://community.tuist.dev).
<!-- -->
:::

### Контекст приложения {#app-context}

Агенту может понадобиться больше контекста о вашем приложении, чтобы хорошо
ориентироваться в нем. У нас есть три типа контекста приложения:
- Описание приложения
- Учетные данные
- Запуск групп аргументов

Все они могут быть настроены в настройках дашборда вашего проекта (`Settings` >
`QA`).

#### Описание приложения {#app-description}

Описание приложения предназначено для предоставления дополнительного контекста о
том, что делает ваше приложение и как оно работает. Это длинное текстовое поле,
которое передается как часть подсказки при запуске агента. Примером может быть:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Учетные данные {#credentials}

Если агенту необходимо войти в приложение, чтобы протестировать некоторые
функции, вы можете предоставить ему учетные данные. Агент заполнит эти учетные
данные, если поймет, что ему нужно войти в систему.

#### Запуск групп аргументации {#launch-argument-groups}

Группы аргументов запуска выбираются на основе запроса на тестирование перед
запуском агента. Например, если вы не хотите, чтобы агент многократно входил в
систему, тратя токены и минуты бегуна, вы можете указать здесь свои учетные
данные. Если агент поймет, что ему следует начать сеанс с входом в систему, то
при запуске приложения он будет использовать группу аргументов запуска с
учетными данными.

![Запуск групп
аргументов](/images/guides/features/qa/launch-argument-groups.png)

Эти аргументы запуска являются стандартными аргументами запуска Xcode. Вот
пример того, как использовать их для автоматического входа в систему:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
