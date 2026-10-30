---
{
  "title": "Apple",
  "titleTemplate": ":title · ბანდლის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გააანალიზეთ iOS, iPadOS, macOS, watchOS და tvOS ბანდლები (.ipa, .xcarchive, .app) Tuist Bundle Insights-ით."
}
---
# Apple {#bundle-insights-apple}

გაანალიზეთ Apple ბანდლი, თუ მიუთითებთ `tuist inspect bundle` არქივს, ინსტალირებად ფაილს ან აწყობილ აპს:

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

როცა macOS-ზე გზის ნაცვლად აპის სახელს გადასცემთ, Tuist პოულობს აწყობილ `.app` Xcode-ის ბილდის პროდუქტებიდან (ითვალისწინებს `--derived-data-path`, თუ მითითებულია), ისევე, როგორც `tuist share`.

ბრძანება ტვირთავს ბანდლს Tuist-ში და აბრუნებს ბმულს დეტალურ მიმოხილვაზე, რომელიც მოიცავს შიგთავსის სკანირებას და მოდულების დაშლას:

![გაანალიზებული ბანდლი](/images/guides/features/bundle-size/analyzed-bundle.png)

## შედარება App Store Connect-თან {#app-store-connect}

Tuist ზომავს ბანდლს ზუსტად ისე, როგორც თქვენ აწვდით და არ იყენებს [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)-ს. მოცემული ზომები შეესაბამება **უნივერსალურ** (დაუთხელებელ) ვარიანტს — App Store Connect-ის აპის ფაილის ზომების ანგარიშში „Universal“ ეტიკეტით მონიშნულ სტრიქონს — და არა მოწყობილობის მიხედვით ვარიანტებს.

მოელით, რომ რიცხვები იქნება Universal სტრიქონის დიაპაზონში, მაგრამ არა იდენტური:

- **ინსტალაციის ზომა** ახლოსაა Universal ინსტალაციის ზომასთან. App Store Connect ოდნავ მეტ მნიშვნელობას აჩვენებს, რადგან ის მოიცავს მოწყობილობაზე ხარჯებს, როგორიცაა ფაილური სისტემის ბლოკების განაწილება და Apple-ის საკუთარი შეფასება, რასაც უბრალო ფაილის ზომის გაზომვა არ ითვალისწინებს.
- **ჩამოტვირთვის ზომა** ნაკლებია Universal ჩამოტვირთვის ზომაზე. Apple აშიფრავს აპის ბინარულ ფაილს ატვირთვის შემდეგ, ხოლო დაშიფრული მონაცემები ნაკლებად ეფექტურად იკუმშება, ამიტომ App Store-ის შეკუმშული ჩამოტვირთვა უფრო დიდია, ვიდრე `.ipa` არქივი, რომელსაც Tuist ზომავს. ეს ხდება Apple-ის მხარეს ატვირთვის შემდეგ, ამიტომ ეს არ აისახება Tuist-ის რიცხვში.

App Store Connect-ში მოწყობილობის მიხედვით სტრიქონები კიდევ უფრო მცირეა, რადგან app thinning აშორებს CPU არქიტექტურებს და ასეთების ვარიანტებს, რომლებიც კონკრეტულ მოწყობილობას არ სჭირდება. Tuist ამჟამად არ აჩვენებს მოწყობილობის მიხედვით (დათხელებულ) ზომებს.

<!-- @snippet: ./_shared -->
