---
{
  "title": "Android",
  "titleTemplate": ":title · ბანდლების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ Android-ის აპლიკაციების ბანდლები (.aab) და ინსტალაციური პაკეტები (.apk) Tuist Bundle Insights-ის გამოყენებით."
}
---
# Android {#bundle-insights-android}

Android-ის ბანდლის ანალიზისთვის მიუთითეთ `tuist inspect bundle` აპლიკაციის ბანდლზე ან დასაყენებელ ფაილზე:

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

ბრძანება ტვირთავს ბანდლს Tuist-ში და აბრუნებს ბმულს დეტალურ მიმოხილვაზე, რომელიც მოიცავს შინაარსის სკანირებასა და მოდულების დაშლას:

![ანალიზებული ბანდლი](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
