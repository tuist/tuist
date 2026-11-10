---
{
  "title": "პრივიუების გაშვება iPhone-ის აპლიკაციით",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "იპოვეთ, ფილტრეთ და მიიღეთ წვდომა Apple-ის პრივიუებზე Tuist-ის iOS აპლიკაციის საშუალებით."
}
---
# პრივიუების გაშვება iPhone-ის აპლიკაციით

დააინსტალირეთ [Tuist iOS აპლიკაცია App Store-დან](https://apps.apple.com/us/app/tuist/id6748460335), რათა იპოვოთ და მიიღოთ წვდომა თქვენს Apple პრივიუებზე. გამოქვეყნების სამუშაო პროცესის ხელმოწერისა და მოწყობილობის შესაბამისობის მოთხოვნები კვლავ ძალაშია.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="ჩამოტვირთეთ App Store-დან" style="height: 40px;">
    </a>
</div>

მოძებნეთ აპლიკაციის სახელით ან გამოშვების შენიშვნებით, შემდეგ კი აირჩიეთ ტრეკი პრივიუების ფილტრაციისთვის. აირჩიეთ **ყველა** ყველა ტრეკის სანახავად, მათ შორის ისეთი პრივიუებისაც, რომლებსაც ტრეკი არ აქვთ. გახსენით პრივიუ, რათა წაიკითხოთ მისი სრული გამოშვების შენიშვნები.

## კლიენტისა და სერვერის თავსებადობა {#client-and-server-compatibility}

შეინარჩუნეთ Tuist აპლიკაცია განახლებული. თუ Tuist-ს საკუთარ სერვერზე მართავთ, განაახლეთ თქვენი სერვერი ტრეკის ფილტრაციისა და გამოშვების შენიშვნების გამოსაყენებლად. ძველ სერვერებზე პრივიუების ნახვა ფილტრაციის გარეშე მაინც შეგიძლიათ.

## აპლიკაციაში განახლების შეტყობინებები {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) საშუალებას აძლევს თქვენს Apple აპლიკაციას აღმოაჩინოს უფრო ახალი პრივიუ და აცნობოს ტესტერებს. ის ამოწმებს განახლებებს იმავე **პრივიუს ტრეკში**. პრივიუებისთვის, რომლებიც გამოქვეყნებულია `tuist share --track`-ით, ის იყენებს იმ ცალსახა ტრეკს. ცალსახა ტრეკის გარეშე, გამოიყენება git ბრენჩი, ამიტომ `main`-დან აგებული პრივიუ მხოლოდ `main`-დან უფრო ახალი პრივიუების შესახებ აცნობებს.

### ინსტალაცია {#sdk-installation}

დაამატეთ Tuist SDK, როგორც Swift Package დამოკიდებულება:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### განახლებების მონიტორინგი {#sdk-monitor-updates}

გამოიყენეთ `monitorPreviewUpdates` პერიოდულად ახალი პრივიუ ვერსიების შესამოწმებლად:

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

### განახლების ერთჯერადი შემოწმება {#sdk-single-check}

ხელით განახლების შესამოწმებლად:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### განახლების მონიტორინგის შეწყვეტა {#sdk-stop-monitoring}

`monitorPreviewUpdates` აბრუნებს `Task`-ს, რომლის გაუქმებაც შესაძლებელია:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> განახლების შემოწმება ავტომატურად გამორთულია სიმულატორებზე და App Store აგებულებზე.
