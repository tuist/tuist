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

Если в macOS вы передаёте имя приложения вместо пути, Tuist находит собранный `.app` среди продуктов сборки Xcode (учитывая `--derived-data-path`, если он задан), так же, как это делает `tuist share` .

<!-- @snippet: ./_upload-result -->

## Сравнение с App Store Connect {#app-store-connect}

Tuist измеряет бандл точно таким, каким вы его предоставляете, и не применяет [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). Указанные размеры соответствуют **универсальному** (без thinning) варианту — строке «Universal» в отчёте о размерах файлов приложения в App Store Connect, а не вариантам для отдельных устройств.

Ожидайте, что числа будут в том же диапазоне, что и строка Universal, но не идентичны:

- **Размер установки** близок к размеру установки Universal. App Store Connect показывает немного большее значение, потому что учитывает накладные расходы на устройстве, такие как выделение блоков файловой системы и собственную оценку Apple, которые не фиксируются при простом измерении размера файла.
- **Размер загрузки** меньше размера загрузки Universal. Apple шифрует бинарный файл приложения после загрузки, а зашифрованные данные сжимаются менее эффективно, поэтому сжатая загрузка из App Store оказывается больше, чем архив `.ipa`, который измеряет Tuist. Это происходит на стороне Apple после загрузки, поэтому не отражается в числе Tuist.

Строки для отдельных устройств в App Store Connect ещё меньше, потому что app thinning удаляет архитектуры CPU и варианты ресурсов, которые конкретному устройству не нужны. В настоящее время Tuist не сообщает размеры для отдельных устройств (с thinning).

<!-- @snippet: ./_shared -->
