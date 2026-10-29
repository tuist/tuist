---
{
  "title": "Apple",
  "titleTemplate": ":title · Аналитика бандлов · Возможности · Руководства · Tuist",
  "description": "Анализируйте бандлы iOS, iPadOS, macOS, watchOS и tvOS (.ipa, .xcarchive, .app) с помощью аналитики бандлов Tuist."
}
---
# Apple {#bundle-insights-apple}

Проанализируйте бандл Apple, указав `tuist inspect bundle` на архив, установочный файл или собранное приложение:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

Если вы передаете имя приложения вместо пути в macOS, Tuist находит собранный `.app` среди продуктов сборки Xcode (учитывая `--derived-data-path`, если он задан), так же, как это делает `tuist share`.

Команда загружает бандл в Tuist и возвращает ссылку на подробный обзор, включая сканирование содержимого и разбивку по модулям:

![Проанализированный бандл](/images/guides/features/bundle-size/analyzed-bundle.png)

## Сравнение с App Store Connect {#app-store-connect}

Tuist измеряет бандл точно в том виде, в котором вы его предоставляете, и не применяет [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). Указанные размеры соответствуют **универсальному** (без прореживания) варианту — строке с меткой «Universal» в отчете о размерах файлов приложения в App Store Connect, а не вариантам для отдельных устройств.

Ожидайте, что числа будут в том же диапазоне, что и в строке Universal, но не идентичны:

- **Размер установки** близок к размеру установки Universal. App Store Connect сообщает немного большее значение, поскольку включает накладные расходы на устройстве, такие как выделение блоков файловой системы и собственная оценка Apple, которые не учитываются при простом измерении размера файла.
- **Размер загрузки** меньше, чем размер загрузки Universal. Apple шифрует бинарный файл приложения после загрузки, а зашифрованные данные сжимаются менее эффективно, поэтому сжатая загрузка в App Store оказывается больше, чем архив `.ipa`, который измеряет Tuist. Это происходит на стороне Apple после загрузки, поэтому не отражается в цифрах Tuist.

Строки для отдельных устройств в App Store Connect еще меньше, потому что app thinning удаляет архитектуры CPU и варианты ресурсов, которые не нужны конкретному устройству. В настоящее время Tuist не сообщает размеры для отдельных устройств (с прореживанием).

<!-- @snippet: ./_shared -->
