---
{
  "title": "Предпросмотры Bazel",
  "titleTemplate": ":title · Предпросмотры · Tuist",
  "description": "Публикуйте приложения для Android, приложения для Apple и инструменты командной строки в виде предпросмотров из Bazel."
}
---
# Превью Bazel

Публикуйте Android APK, приложения для симулятора Apple и macOS, а также инструменты командной строки из ваших существующих целей Bazel. Добавьте цель превью для каждого артефакта, которым хотите поделиться; ваши обычные сборки останутся без изменений.

## Настройка

Добавьте [`rules_tuist` из репозитория Tuist](https://github.com/tuist/tuist/tree/main/bazel) в `MODULE.bazel`, зафиксировав нужный коммит:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Сохраните существующие цели приложений, нативные SDK и настройки подписи. Bazel предоставляет инструменты для публикации.

Войдите прямо из Bazel:

```bash
bazel run @rules_tuist//:login
```

Это разделяет учетные данные с CLI Tuist и плагином Gradle; уже выполненная авторизация тоже подойдет. В CI используйте `TUIST_TOKEN` или запустите цель входа с <.localized_link href="/guides/integrations/continuous-integration">OIDC-аутентификацией</.localized_link> от Tuist. Никогда не храните учетные данные в файлах BUILD или атрибутах правил. Передайте `-- --url https://tuist.example.com`, чтобы войти в самостоятельно размещенный экземпляр.

Загружайте только необходимый адаптер в вашем `BUILD.bazel`:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Для приложений Apple:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

Для исполняемых целей, таких как `cc_binary`:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

Превью исполняемого файла включает файлы времени выполнения, объявленные в цели. Объявите библиотеки и ресурсы, необходимые вашему инструменту, в его цели Bazel и используйте пути, которые работают вне каталога сборки.

## Сборка и публикация

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Замените метки приложений и платформ симулятора на свои. Передайте `--url` для самостоятельно размещенного источника Tuist и `--revision`, чтобы связать коммит Git.

Передайте `--publish --project account/project`, чтобы поделиться успешной сборкой. Без `--publish` или с `--no-publish` ничего не загружается, и вход в систему не требуется. Обычный `bazel build` никогда не публикует, даже при попадании в кэш. `tuist bazel setup` включает кэширование и аналитику, но не публикацию.

## Поддерживаемые артефакты

- **Android:** подписанные APK приложений, включая отладочные сборки. Установите инструменты сборки и инструменты командной строки Android SDK и задайте `ANDROID_HOME` или `ANDROID_SDK_ROOT`. Тестовые APK и Android App Bundles не поддерживаются.
- **Apple:** приложения для симулятора и macOS с ad-hoc подписью, собранные и проверенные на macOS. Сборки для физических устройств, фреймворки, расширения и тесты не поддерживаются. Используйте архивные выходные данные вместо экспериментальных древовидных архивов.
- **Инструменты командной строки:** исполняемые файлы macOS или Linux для arm64 или x86_64, включая универсальные бинарные файлы macOS. Скрипты требуют shebang и наличия интерпретатора в системе получателя. Объявите зависимости времени выполнения в вашей цели; Tuist не устанавливает отсутствующие библиотеки или среды выполнения языков.

## Повторное использование кэша, сбои и хранение

Повторение той же публикации повторно использует существующее превью без повторной загрузки, даже если Bazel восстанавливает сборку из кэша. Изменение выходных данных, трека или ревизии создает новую публикацию. Сбой загрузки приводит к ошибке команды; вы можете перезапустить ее, чтобы проверить, завершилась ли публикация, прежде чем пробовать снова.

Команда предоставляет ссылку на превью вашего проекта, где обработка может занять некоторое время. Превью используют видимость по умолчанию проекта.

Публикации артефактов истекают через 30 дней в размещенном Tuist. Самостоятельно размещенные экземпляры используют `TUIST_APP_PREVIEW_RETENTION_DAYS`; если значение не задано, срок действия для этого семейства отключается. Истекшие записи публикаций нельзя восстановить, повторно выполнив ту же команду.

См. <.localized_link href="/guides/features/previews#run-a-preview">Запуск превью</.localized_link> для информации о запуске опубликованных сборок, доступе, треках и бейджах README.

## Превью Apple

Для превью симулятора Apple и macOS см. <.localized_link href="/guides/features/previews/run/macos">инструкции по приложению-компаньону Tuist для macOS</.localized_link>. Это не меняет требования Bazel к пригодности приложений или подписи.

## Связанные рабочие процессы {#publish-from-once}

Существующие интеграции Once имеют отдельное <.localized_link href="/guides/features/previews/once">руководство по публикации артефактов</.localized_link>. Оба рабочих процесса сохраняют публикацию отдельно от выполнения кэшированного графа.
