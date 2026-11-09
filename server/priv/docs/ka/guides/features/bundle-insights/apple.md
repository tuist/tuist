---
{
  "title": "Apple",
  "titleTemplate": ":title · ბანდლის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ iOS, iPadOS, macOS, watchOS და tvOS ბანდლები (.ipa, .xcarchive, .app) Tuist Bundle Insights-ით."
}
---
# Apple {#bundle-insights-apple}

გაანალიზეთ Apple ბანდლი, თუ `tuist inspect bundle`-ს მიუთითებთ არქივზე, დასაყენებელ ფაილზე ან აწყობილ აპლიკაციაზე:

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

როცა macOS-ზე გზის ნაცვლად აპლიკაციის სახელს გადასცემთ, Tuist პოულობს აწყობილ `.app` Xcode-ის აწყობის პროდუქტებიდან (ითვალისწინებს `--derived-data-path`-ს, თუ მითითებულია), ისევე, როგორც `tuist share`.

<!-- @snippet: ./_upload-result -->

## შედარება App Store Connect-თან {#app-store-connect}

Tuist ზომავს ბანდლს ზუსტად ისე, როგორც თქვენ აწვდით, და არ იყენებს [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)-ს. მოცემული ზომები შეესაბამება **უნივერსალურ** (არა-thinned) ვარიანტს — App Store Connect-ის აპლიკაციის ფაილების ზომების ანგარიშში „Universal“ ეტიკეტით მონიშნულ სტრიქონს — და არა მოწყობილობის მიხედვით ვარიანტებს.

მოელით, რომ რიცხვები იქნება Universal სტრიქონის დიაპაზონში, მაგრამ არა იდენტური:

- **დაყენების ზომა** ახლოსაა Universal დაყენების ზომასთან. App Store Connect ოდნავ მეტ მნიშვნელობას აჩვენებს, რადგან ის მოიცავს მოწყობილობაზე არსებულ დამატებით ხარჯებს, როგორიცაა ფაილური სისტემის ბლოკების გამოყოფა და Apple-ის საკუთარი შეფასება, რასაც უბრალო ფაილის ზომის გაზომვა არ ითვალისწინებს.
- **ჩამოტვირთვის ზომა** ნაკლებია Universal ჩამოტვირთვის ზომაზე. Apple აპლიკაციის ბინარულ ფაილს ატვირთვის შემდეგ აშიფრავს, ხოლო დაშიფრული მონაცემები ნაკლებად ეფექტურად იკუმშება, ამიტომ App Store-ის შეკუმშული ჩამოტვირთვა უფრო დიდია, ვიდრე `.ipa` არქივი, რომელსაც Tuist ზომავს. ეს ხდება Apple-ის მხარეს ატვირთვის შემდეგ, ამიტომ ეს არ აისახება Tuist-ის რიცხვში.

App Store Connect-ში მოწყობილობის მიხედვით სტრიქონები კიდევ უფრო მცირეა, რადგან app thinning შლის CPU არქიტექტურებს და ასეტების ვარიანტებს, რომლებიც კონკრეტულ მოწყობილობას არ სჭირდება. Tuist ამჟამად არ აჩვენებს მოწყობილობის მიხედვით (thinned) ზომებს.

<!-- @snippet: ./_shared -->
