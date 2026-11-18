---
{
  "title": "Android",
  "titleTemplate": ":title · ბანდლების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist Bundle Insights-ის გამოყენებით შეისწავლეთ Android-ის აპლიკაციების ბანდლები (.aab) და ინსტალაციური პაკეტები (.apk)."
}
---
# Android {#bundle-insights-android}

Android ბანდლის ანალიზისთვის მიმართეთ `tuist inspect bundle` აპლიკაციის ბანდლს ან დასაყენებელ ფაილს:

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
> **`.apk`-ის ანალიზი მოითხოვს `aapt2`-ს**, რომელიც შედის Android SDK build tools-ში. დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`, რათა Tuist-მა იპოვოს ის, ან დაამატეთ `aapt2` `PATH`-ზე. `.aab`-ის ანალიზს გარე ხელსაწყოები არ სჭირდება.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
