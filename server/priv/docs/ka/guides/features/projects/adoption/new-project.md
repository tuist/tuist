---
{
  "title": "ახალი პროექტის შექმნა",
  "titleTemplate": ":title · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ ახალი პროექტი Tuist-ით."
}
---
# ახალი პროექტის შექმნა {#create-a-new-project}

Tuist-ით ახალი პროექტის დაწყების ყველაზე მარტივი გზა არის `tuist init` ბრძანების გამოყენება. ეს ბრძანება იწყებს ინტერაქციულ CLI-ს, რომელიც მიგიყვანთ პროექტის კონფიგურაციამდე. მოთხოვნისას დარწმუნდით, რომ აირჩიეთ „გენერირებული პროექტის“ შექმნის ვარიანტი.

შემდეგ შეგიძლიათ <.localized_link href="/guides/features/projects/editing">პროექტის რედაქტირება</.localized_link> `tuist edit` ბრძანების გაშვებით, რის შემდეგაც Xcode გახსნის პროექტს რედაქტირებისთვის. გენერირებულ ფაილებს შორის არის `Project.swift`, რომელიც შეიცავს თქვენი პროექტის განსაზღვრას. თუ ნაცნობია Swift Package Manager, წარმოიდგინეთ ის როგორც `Package.swift`, მაგრამ Xcode-ის პროექტების ტერმინოლოგიით.

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
> ჩვენ განზრახ ვინარჩუნებთ ხელმისაწვდომი შაბლონების სიას მოკლედ, რათა შევამციროთ მხარდაჭერის დატვირთვა. თუ გსურთ შექმნათ პროექტი, რომელიც არ არის აპლიკაცია (მაგალითად, ფრეიმვორკი), შეგიძლიათ გამოიყენოთ `tuist init` საწყის წერტილად და შემდეგ შეცვალოთ გენერირებული პროექტი თქვენი საჭიროებების შესაბამისად.


## პროექტის ხელით შექმნა {#manually-creating-a-project}

ალტერნატიულად, შეგიძლიათ პროექტი ხელით შექმნათ. ამას ვურჩევთ მხოლოდ მაშინ, თუ უკვე იცნობთ Tuist-ს და მის კონცეფციებს. პირველი ნაბიჯი იქნება პროექტის სტრუქტურისთვის დამატებითი საქაღალდეების შექმნა:

```bash
mkdir MyFramework
cd MyFramework
```

შემდეგ შექმენით `Tuist.swift` ფაილი, რომელიც აკონფიგურირებს Tuist-ს და გამოიყენება პროექტის ძირითადი საქაღალდის დასადგენად, ასევე `Project.swift`, სადაც განისაზღვრება თქვენი პროექტი:

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
> Tuist იყენებს `Tuist/` საქაღალდეს თქვენი პროექტის ძირის დასადგენად და იქიდან ეძებს სხვა მანიფესტ ფაილებს საქაღალდეებში. გირჩევთ, ეს ფაილები შექმნათ თქვენი არჩევითი რედაქტორით, რის შემდეგაც შეგიძლიათ გამოიყენოთ `tuist edit` პროექტის Xcode-ში რედაქტირებისთვის.
