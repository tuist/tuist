---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle insights · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist Bundle Insights-ის გამოყენებით გააანალიზეთ Android-ის აპლიკაციების ბანდლები (.aab) და ინსტალაციური პაკეტები (.apk)."
}
---
# Android {#bundle-insights-android}

Android ბანდლის ანალიზისთვის მიმართეთ `tuist inspect bundle` აპლიკაციის ბანდლს ან ინსტალირებად ფაილს:

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
> **`.apk`-ის ანალიზს სჭირდება `aapt2`**, რომელიც Android SDK build tools-თან ერთად მოდის. დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`, რათა Tuist-მა იპოვოს ის, ან დაამატეთ `aapt2` `PATH`-ში. `.aab`-ის ანალიზს გარე ხელსაწყოები არ სჭირდება.

ბრძანება ტვირთავს ბანდლს Tuist-ზე და აბრუნებს ბმულს დეტალურ მიმოხილვაზე, რომელიც მოიცავს შიგთავსის სკანირებასა და მოდულების დეტალურ ჩამონათვალს:

![ანალიზებული ბანდლი](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
