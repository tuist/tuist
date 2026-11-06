---
{
  "title": "Android",
  "titleTemplate": ":title · ბანდლის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist Bundle Insights-ით გააანალიზეთ Android-ის აპლიკაციების ბანდლები (.aab) და ინსტალაციური პაკეტები (.apk)."
}
---
# Android {#bundle-insights-android}

გაანალიზეთ Android ბანდლი, თუ `tuist inspect bundle`-ს მიუთითებთ აპის ბანდლს ან დასაყენებელ ფაილს:

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
> **`.apk`-ის ანალიზს სჭირდება `aapt2`**, რომელიც შედის Android SDK build tools-ში. დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`, რათა Tuist-მა იპოვოს ის, ან დაამატეთ `aapt2` `PATH`-ზე. `.aab`-ის ანალიზს გარე ინსტრუმენტები არ სჭირდება.

ბრძანება ატვირთავს ბანდლს Tuist-ში და აბრუნებს ბმულს დეტალურ გადახედვაზე, რომელიც მოიცავს შიგთავსის სკანირებასა და მოდულების დაშლას:

![გაანალიზებული ბანდლი](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
