---
{
  "title": "ახალი პროექტის შექმნა",
  "titleTemplate": ":title · ინტეგრაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ ახალი პროექტი Tuist-ით."
}
---
# ახალი პროექტის შექმნა {#create-a-new-project}

Tuist-ით ახალი პროექტის დაწყების ყველაზე მარტივი გზაა `tuist init` ბრძანების გამოყენება. ეს ბრძანება აშვებს ინტერაქტიულ CLI-ს, რომელიც მიგიყვანთ პროექტის კონფიგურაციის პროცესში. მოთხოვნისას დარწმუნდით, რომ აირჩიეთ „გენერირებული პროექტის“ შექმნის ვარიანტი.

შემდეგ შეგიძლიათ <.localized_link href="/guides/features/projects/editing">პროექტის რედაქტირება</.localized_link> `tuist edit` გაშვებით, რის შემდეგაც Xcode გახსნის პროექტს, სადაც შეძლებთ მის რედაქტირებას. გენერირებულ ფაილებს შორის არის `Project.swift`, რომელიც შეიცავს თქვენი პროექტის განსაზღვრებას. თუ გაქვთ გამოცდილება Swift Package Manager-თან, წარმოიდგინეთ ის როგორც `Package.swift`, მაგრამ Xcode-ის პროექტების ტერმინოლოგიით.

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
> ჩვენ განზრახვით ვინარჩუნებთ ხელმისაწვდომი შაბლონების სიას მოკლედ, რათა შევამციროთ მხარდაჭერის დამატებითი დატვირთვა. თუ გსურთ შექმნათ პროექტი, რომელიც არ არის აპლიკაცია, მაგალითად, ფრეიმვორკი, შეგიძლიათ გამოიყენოთ `tuist init` საწყის წერტილად და შემდეგ შეცვალოთ გენერირებული პროექტი თქვენი საჭიროებების შესაბამისად.


## პროექტის ხელით შექმნა {#manually-creating-a-project}

ალტერნატიულად, შეგიძლიათ პროექტი ხელით შექმნათ. ამას ვურჩევთ მხოლოდ იმ შემთხვევაში, თუ უკვე იცნობთ Tuist-ს და მის ცნებებს. პირველი ნაბიჯი იქნება პროექტის სტრუქტურისთვის დამატებითი დირექტორიების შექმნა:

```bash
mkdir MyFramework
cd MyFramework
```

შემდეგ შექმენით `Tuist.swift` ფაილი, რომელიც აკონფიგურირებს Tuist-ს და გამოიყენება პროექტის ფესვის დირექტორიის დასადგენად, ასევე `Project.swift`, სადაც განაცხადებთ თქვენს პროექტს:

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
> Tuist იყენებს `Tuist/` დირექტორიას პროექტის ფესვის დასადგენად და იქიდან ეძებს სხვა მანიფესტ ფაილებს დირექტორიებში. გირჩევთ, ეს ფაილები შექმნათ თქვენი არჩეული რედაქტორით და ამის შემდეგ გამოიყენოთ `tuist edit` პროექტის Xcode-ში რედაქტირებისთვის.
