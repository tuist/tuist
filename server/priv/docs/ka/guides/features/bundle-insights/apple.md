---
{
  "title": "Apple",
  "titleTemplate": ":title · ბანდლების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ iOS, iPadOS, macOS, watchOS და tvOS ბანდლები (.ipa, .xcarchive, .app) Tuist Bundle Insights-ით."
}
---
# Apple {#bundle-insights-apple}

Apple-ის ბანდლის ანალიზი შესაძლებელია `tuist inspect bundle`-ის გამოყენებით არქივზე, დასაყენებელ ფაილზე ან აწყობილ აპლიკაციაზე მიმართვით:

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

როცა macOS-ზე გზის ნაცვლად აპლიკაციის სახელს გადასცემთ, Tuist პოულობს აწყობილ `.app` Xcode-ის აწყობის პროდუქტებიდან (ითვალისწინებს `--derived-data-path`, თუ მითითებულია), ისევე, როგორც `tuist share`.

<!-- @snippet: ./_upload-result -->

## შედარება App Store Connect-თან {#app-store-connect}

Tuist ზომავს ბანდლს ზუსტად იმ სახით, როგორც თქვენ აწვდით და არ იყენებს [აპლიკაციის შევიწროებას](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). მოხსენებული ზომები შეესაბამება **უნივერსალურ** (შეუვიწროებელ) ვარიანტს — App Store Connect-ის აპლიკაციის ფაილების ზომების ანგარიშში „Universal“ ეტიკეტით მონიშნულ სტრიქონს — და არა თითოეული მოწყობილობისთვის განკუთვნილ ვარიანტებს.

მოელით, რომ რიცხვები იქნება Universal სტრიქონის დიაპაზონში, მაგრამ არა იდენტური:

- **დაყენების ზომა** ახლოსაა Universal დაყენების ზომასთან. App Store Connect ოდნავ მეტ მნიშვნელობას აჩვენებს, რადგან ის მოიცავს მოწყობილობაზე არსებულ დამატებით ხარჯებს, როგორიცაა ფაილური სისტემის ბლოკების განაწილება და Apple-ის საკუთარი შეფასება, რასაც უბრალო ფაილის ზომის გაზომვა არ ითვალისწინებს.
- **ჩამოტვირთვის ზომა** ნაკლებია Universal ჩამოტვირთვის ზომაზე. Apple აპლიკაციის ბინარულ ფაილს ატვირთვის შემდეგ აშიფრავს, ხოლო დაშიფრული მონაცემები ნაკლებად ეფექტურად იკუმშება, ამიტომ App Store-ის შეკუმშული ჩამოტვირთვა საბოლოოდ უფრო დიდია, ვიდრე `.ipa` არქივი, რომელსაც Tuist ზომავს. ეს პროცესი ხდება Apple-ის მხარეს ატვირთვის შემდეგ, ამიტომ ის არ აისახება Tuist-ის მონაცემებში.

App Store Connect-ში თითოეული მოწყობილობის სტრიქონები კიდევ უფრო მცირეა, რადგან აპლიკაციის შევიწროება აშორებს CPU არქიტექტურებს და რესურსების ვარიანტებს, რომლებიც კონკრეტულ მოწყობილობას არ სჭირდება. Tuist ამჟამად არ აჩვენებს თითოეული მოწყობილობისთვის (შევიწროებულ) ზომებს.

<!-- @snippet: ./_shared -->
