---
{
  "title": "Android",
  "titleTemplate": ":title · ბანდლის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ Android-ის აპლიკაციების ბანდლები (.aab) და ინსტალაციური პაკეტები (.apk) Tuist Bundle Insights-ით."
}
---
# Android {#bundle-insights-android}

გაანალიზეთ Android ბანდლი, მიუთითეთ `tuist inspect bundle` აპის ბანდლზე ან დასაყენებელ ფაილზე:

::: code-group
```bash [Analyze an .aab (recommended)]
tuist inspect bundle App.aab
```
```bash [Analyze an .apk]
tuist inspect bundle App.apk
```
<!-- -->
:::

> [!NOTE]
> **`.apk`-ის გასაანალიზებლად საჭიროა `aapt2`**, რომელიც შედის Android SDK build tools-ში. დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`, რათა Tuist-მა იპოვოს ის, ან დაამატეთ `aapt2` `PATH`-ში. `.aab`-ის გასაანალიზებლად გარე ხელსაწყოები არ არის საჭირო.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
