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
Tuist QA в настоящее время находится на ранней стадии предварительного
просмотра. Зарегистрируйтесь на [tuist.dev/qa](https://tuist.dev/qa), чтобы
получить доступ.
<!-- -->
:::

Качественная разработка мобильных приложений зависит от всестороннего
тестирования, но традиционные подходы имеют свои ограничения. Модульные тесты
быстры и экономичны, но они не учитывают реальные сценарии использования
пользователями. Приемочные тесты и ручной контроль качества могут устранить эти
пробелы, но они требуют больших ресурсов и плохо масштабируются.

Агент QA Tuist решает эту проблему, имитируя поведение реального пользователя.
Он самостоятельно исследует ваше приложение, распознает элементы интерфейса,
выполняет реалистичные взаимодействия и отмечает потенциальные проблемы. Такой
подход помогает выявлять ошибки и проблемы с удобством использования на ранних
этапах разработки, избегая при этом накладных расходов и бремени обслуживания,
связанных с традиционным приемочным и QA-тестированием.

## Предварительные условия {#prerequisites}

Чтобы начать использовать Tuist QA, вам необходимо:
- Настройте загрузку
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> из
  вашего рабочего процесса PR CI, который агент может затем использовать для
  тестирования.
- <LocalizedLink href="/guides/integrations/gitforge/github">Интегрируйте
  </LocalizedLink> с GitHub, чтобы вы могли запускать агент прямо из вашего PR.

## Использование {#usage}

Tuist QA в настоящее время запускается непосредственно из PR. После того, как у
вас появится предварительный просмотр, связанный с вашим PR, вы можете запустить
агент QA, добавив комментарий `/qa test I want to test feature A` в PR:

![QA trigger comment](/images/guides/features/qa/qa-trigger-comment.png)

Комментарий содержит ссылку на сеанс в режиме реального времени, где вы можете
увидеть прогресс агента QA и любые обнаруженные им проблемы. После завершения
работы агент отправит сводку результатов обратно в PR:

![QA test summary](/images/guides/features/qa/qa-test-summary.png)

В рамках отчета в панели инструментов, на который ссылается комментарий PR, вы
получите список проблем и временную шкалу, чтобы вы могли проверить, как именно
возникла проблема:

![QA timeline](/images/guides/features/qa/qa-timeline.png)

Вы можете увидеть все проверки качества, которые мы проводим для нашего
<LocalizedLink href="/guides/features/previews#tuist-ios-app">приложения для
iOS</LocalizedLink>, в нашей общедоступной панели инструментов:
https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
Агент QA работает автономно и не может быть прерван дополнительными запросами
после запуска. Мы предоставляем подробные журналы на протяжении всего
выполнения, чтобы помочь вам понять, как агент взаимодействовал с вашим
приложением. Эти журналы ценны для итерации контекста вашего приложения и
тестирования подсказок, чтобы лучше направлять поведение агента. Если у вас есть
отзывы о том, как агент работает с вашим приложением, сообщите нам об этом через
[GitHub Issues](https://github.com/tuist/tuist/issues), наше [сообщество
Slack](https://slack.tuist.dev) или наш [форум
сообщества](https://community.tuist.dev).
<!-- -->
:::

### Контекст приложения {#app-context}

Агенту может понадобиться дополнительная информация о вашем приложении, чтобы он
мог хорошо в нем ориентироваться. У нас есть три типа контекста приложения:
- Описание приложения
- Удостоверения
- Группы аргументов запуска

Все эти настройки можно изменить в панели управления вашего проекта (`Настройки`
> `QA`).

#### Описание приложения {#app-description}

Описание приложения предназначено для предоставления дополнительного контекста о
том, что делает ваше приложение и как оно работает. Это длинное текстовое поле,
которое передается как часть подсказки при запуске агента. Пример:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Удостоверения {#credentials}

Если агенту необходимо войти в приложение для тестирования некоторых функций, вы
можете предоставить ему учетные данные для входа. Агент введет эти учетные
данные, если поймет, что ему необходимо войти в систему.

#### Группы аргументов запуска {#launch-argument-groups}

Группы аргументов запуска выбираются на основе вашего тестового запроса перед
запуском агента. Например, если вы не хотите, чтобы агент повторно входил в
систему, тратя ваши токены и минуты работы, вы можете указать здесь свои учетные
данные. Если агент распознает, что ему следует начать сеанс с входом в систему,
он будет использовать группу аргументов запуска с учетными данными при запуске
приложения.

![Группы аргументов
запуска](/images/guides/features/qa/launch-argument-groups.png)

Эти аргументы запуска являются стандартными аргументами запуска Xcode. Вот
пример того, как их использовать для автоматического входа в систему:

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
