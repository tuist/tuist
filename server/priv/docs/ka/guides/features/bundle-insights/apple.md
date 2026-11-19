---
{
  "title": "Apple",
  "titleTemplate": ":title · ბანდლის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ iOS, iPadOS, macOS, watchOS და tvOS ბანდლები (.ipa, .xcarchive, .app) Tuist Bundle Insights-ით."
}
---
# Apple {#bundle-insights-apple}

გაანალიზეთ Apple ბანდლი, თუ `tuist inspect bundle` მიუთითებთ არქივს, დაყენებად ფაილს ან აწყობილ აპლიკაციას:

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

როცა macOS-ზე გზის ნაცვლად აპლიკაციის სახელს გადასცემთ, Tuist პოულობს აწყობილ `.app` Xcode-ის აწყობის პროდუქტებიდან (ითვალისწინებს `--derived-data-path`, თუ მითითებულია), ისევე როგორც `tuist share`.

<!-- @snippet: ./_upload-result -->

## შედარება App Store Connect-თან {#app-store-connect}

Tuist ზომავს ბანდლს ზუსტად იმ სახით, როგორც თქვენ აწვდით და არ იყენებს [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)-ს. მოცემული ზომები შეესაბამება **უნივერსალურ** (შეუმცირებელ) ვარიანტს — App Store Connect-ის აპლიკაციის ფაილების ზომების ანგარიშში „Universal“ ეტიკეტით მონიშნულ სტრიქონს — და არა თითოეული მოწყობილობისთვის განკუთვნილ ვარიანტებს.

მოელით, რომ რიცხვები Universal სტრიქონის დიაპაზონში იქნება, მაგრამ არა იდენტური:

- **დაყენების ზომა** ახლოსაა Universal დაყენების ზომასთან. App Store Connect ოდნავ მეტ მნიშვნელობას აჩვენებს, რადგან ის მოიცავს მოწყობილობაზე არსებულ დამატებით ხარჯებს, როგორიცაა ფაილური სისტემის ბლოკების გამოყოფა და Apple-ის საკუთარი შეფასება, რასაც უბრალო ფაილის ზომის გაზომვა ვერ იჭერს.
- **ჩამოტვირთვის ზომა** ნაკლებია Universal ჩამოტვირთვის ზომაზე. Apple აპლიკაციის ბინარულ ფაილს ატვირთვის შემდეგ აშიფრავს, ხოლო დაშიფრული მონაცემები ნაკლებად ეფექტურად იკუმშება, ამიტომ App Store-ის შეკუმშული ჩამოტვირთვა უფრო დიდია, ვიდრე `.ipa` არქივი, რომელსაც Tuist ზომავს. ეს პროცესი Apple-ის მხარეს ხდება ატვირთვის შემდეგ, ამიტომ ის Tuist-ის რიცხვებში არ აისახება.

App Store Connect-ში თითოეული მოწყობილობისთვის განკუთვნილი სტრიქონები კიდევ უფრო მცირეა, რადგან app thinning შლის CPU არქიტექტურებს და ასეთების ვარიანტებს, რომლებიც კონკრეტულ მოწყობილობას არ სჭირდება. Tuist ამჟამად არ აჩვენებს თითოეული მოწყობილობისთვის (შემცირებულ) ზომებს.

<!-- @snippet: ./_shared -->
