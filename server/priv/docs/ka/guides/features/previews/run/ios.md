---
{
  "title": "პრევიუების გაშვება iPhone-ის აპლიკაციით",
  "titleTemplate": ":title · პრევიუები · Tuist",
  "description": "იპოვეთ, გაფილტრეთ და მიუწვდეთ Apple-ის პრევიუებს Tuist-ის iOS აპლიკაციით."
}
---
# პრივიუების გაშვება iPhone-ის აპლიკაციით

დააინსტალირეთ [Tuist iOS აპლიკაცია App Store-დან](https://apps.apple.com/us/app/tuist/id6748460335), რათა იპოვოთ და მიუწვდეთ თქვენს Apple პრივიუებს. გამოქვეყნების სამუშაო პროცესის ხელმოწერისა და მოწყობილობის შესაბამისობის მოთხოვნები კვლავ ძალაშია.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="ჩამოტვირთვა App Store-დან" style="height: 40px;">
    </a>
</div>

მოძებნეთ აპლიკაციის სახელით ან გამოშვების შენიშვნებით, შემდეგ აირჩიეთ ტრეკი პრივიუების ფილტრაციისთვის. აირჩიეთ **ყველა**, რათა დაათვალიეროთ ყველა ტრეკი, მათ შორის ის პრივიუებიც, რომლებსაც ტრეკი არ აქვთ. გახსენით პრივიუ, რათა წაიკითხოთ მისი სრული გამოშვების შენიშვნები.

## კლიენტისა და სერვერის თავსებადობა {#client-and-server-compatibility}

აქციეთ Tuist აპლიკაცია განახლებული. თუ Tuist-ს თვითმასპინძლობთ, განაახლეთ თქვენი სერვერი, რათა გამოიყენოთ ტრეკის ფილტრაცია და გამოშვების შენიშვნები. ძველ სერვერებზე პრივიუების დათვალიერება ფილტრაციის გარეშე მაინც შეგიძლიათ.

## აპლიკაციაში განახლების შეტყობინებები {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) საშუალებას აძლევს თქვენს Apple აპლიკაციას აღმოაჩინოს უფრო ახალი პრივიუ და შეატყობინოს ტესტერებს. ის ამოწმებს განახლებებს იმავე **პრივიუს ტრეკში**. პრივიუებისთვის, რომლებიც გამოქვეყნებულია `tuist share --track`-ით, ის იყენებს ამ ცალსახა ტრეკს. ცალსახა ტრეკის გარეშე გამოიყენება git ბრენჩი, ამიტომ `main`-დან აგებული პრივიუ მხოლოდ `main`-დან უფრო ახალი პრივიუების შესახებ ატყობინებს.

### ინსტალაცია {#sdk-installation}

დაამატეთ Tuist SDK, როგორც Swift Package დამოკიდებულება:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### განახლებების მონიტორინგი {#sdk-monitor-updates}

გამოიყენეთ `monitorPreviewUpdates`, რათა პერიოდულად შეამოწმოთ პრივიუს ახალი ვერსიები:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### ერთჯერადი განახლების შემოწმება {#sdk-single-check}

ხელით განახლების შემოწმებისთვის:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### განახლების მონიტორინგის შეჩერება {#sdk-stop-monitoring}

`monitorPreviewUpdates` აბრუნებს `Task`-ს, რომლის გაუქმებაც შესაძლებელია:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> განახლების შემოწმება ავტომატურად გამორთულია სიმულატორებზე და App Store-ის აგებულებებზე.
