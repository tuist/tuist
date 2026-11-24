---
{
  "title": "ახალი პროექტის შექმნა",
  "titleTemplate": ":title · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ ახალი პროექტი Tuist-ით."
}
---
# ახალი პროექტის შექმნა {#create-a-new-project}

Tuist-ით ახალი პროექტის დაწყების ყველაზე მარტივი გზაა `tuist init` ბრძანების გამოყენება. ეს ბრძანება запускает ინტერაქტიულ CLI-ს, რომელიც მიგიყვანთ პროექტის კონფიგურაციამდე. მოთხოვნისას დარწმუნდით, რომ აირჩიეთ „generated project“-ის შექმნის ვარიანტი.

შემდეგ შეგიძლიათ <.localized_link href="/guides/features/projects/editing">პროექტის რედაქტირება</.localized_link> `tuist edit`-ის გაშვებით, რის შემდეგაც Xcode გახსნის პროექტს რედაქტირებისთვის. გენერირებული ფაილებიდან ერთ-ერთია `Project.swift`, რომელიც შეიცავს თქვენი პროექტის განსაზღვრას. თუ ნაცნობია Swift Package Manager, წარმოიდგინეთ ის როგორც `Package.swift`, მაგრამ Xcode-ის პროექტების ტერმინოლოგიით.

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> ჩვენ განზრახვით ვინარჩუნებთ ხელმისაწვდომი შაბლონების სიას მოკლედ, რათა შევამციროთ მხარდაჭერის დამატებითი დატვირთვა. თუ გსურთ შექმნათ პროექტი, რომელიც არ წარმოადგენს აპლიკაციას, მაგალითად ფრეიმვორკს, შეგიძლიათ გამოიყენოთ `tuist init` საწყის წერტილად და შემდეგ შეცვალოთ გენერირებული პროექტი თქვენი საჭიროებების შესაბამისად.


## პროექტის ხელით შექმნა {#manually-creating-a-project}

ალტერნატიულად, შეგიძლიათ პროექტი ხელით შექმნათ. ამას ვურჩევთ მხოლოდ მაშინ, თუ უკვე ნაცნობია Tuist და მისი კონცეფციები. პირველი, რაც უნდა გააკეთოთ, არის პროექტის სტრუქტურისთვის დამატებითი დირექტორიების შექმნა:

```bash
mkdir MyFramework
cd MyFramework
```

შემდეგ შექმენით `Tuist.swift` ფაილი, რომელიც დააკონფიგურირებს Tuist-ს და გამოიყენება პროექტის ძირითადი დირექტორიის დასადგენად, ასევე `Project.swift`, სადაც განისაზღვრება თქვენი პროექტი:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

> [!WARNING]
> Tuist იყენებს `Tuist/` დირექტორიას პროექტის ძირის დასადგენად და იქიდან ეძებს სხვა manifest ფაილებს დირექტორიებში. ვურჩევთ, შექმნათ ეს ფაილები თქვენი არჩეული რედაქტორით, რის შემდეგაც შეგიძლიათ გამოიყენოთ `tuist edit` პროექტის Xcode-ში რედაქტირებისთვის.
