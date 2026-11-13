---
{
  "title": "გენერირებული პროექტის შექმნა",
  "titleTemplate": ":title · Xcode · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ თქვენი პირველი Tuist-ით გენერირებული Xcode პროექტი და დაამატოთ მას დამოკიდებულებები"
}
---
# შექმენით გენერირებული პროექტი {#create-a-generated-project}

გაუშვით `tuist init` ცარიელ დირექტორიაში ან არსებული პროექტის დირექტორიაში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება მიგიყვანთ ნაბიჯ-ნაბიჯ <.localized_link href="/guides/features/projects">გენერირებული პროექტის შექმნამდე</.localized_link> ან არსებული Xcode პროექტის ან სამუშაო სივრცის ინტეგრაციამდე. ის გეხმარებათ დააკავშიროთ თქვენი გარემო удаленный სერვერთან, რაც გაძლევთ წვდომას ისეთ ფუნქციებზე, როგორიცაა <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირება</.localized_link>, <.localized_link href="/guides/features/previews">წინასწარი ჩვენებები</.localized_link> და <.localized_link href="/guides/features/package-registries/swift">რეესტრი</.localized_link>.

> [!NOTE]
> **არსებული პროექტის მიგრაცია**
>
> თუ გსურთ არსებული პროექტის გადატანა გენერირებულ პროექტებზე დეველოპერის გამოცდილების გასაუმჯობესებლად და ჩვენი <.localized_link href="/guides/features/cache">ქეშის</.localized_link> გამოყენებისთვის, იხილეთ ჩვენი <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">მიგრაციის სახელმძღვანელო</.localized_link>.


## დამატეთ დამოკიდებულებები {#add-dependencies}

ხშირია, რომ პროექტები ეყრდნობიან მესამე მხარის ბიბლიოთეკებს დამატებითი ფუნქციონალის მისაღებად. ამისთვის გაუშვით შემდეგი ბრძანება, რათა უზრუნველყოთ პროექტის რედაქტირების საუკეთესო გამოცდილება:

```bash
tuist edit
```

გაიხსნება Xcode პროექტი, რომელიც შეიცავს თქვენს პროექტის ფაილებს. ჩაასწორეთ `Tuist/Package.swift` და დაამატეთ Kingfisher:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

შემდეგ ჩაასწორეთ თქვენი პროექტის აპლიკაციის target, რათა განაცხადოთ `Kingfisher` როგორც დამოკიდებულება:

```swift
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
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            buildableFolders: [
                "MyApp/Sources",
                "MyApp/Resources",
            ],
            dependencies: [
                .external(name: "Kingfisher")
            ]
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

შემდეგ გაუშვით `tuist install`, რათა ამოიცნოთ და ჩამოიტანოთ დამოკიდებულებები [Swift Package Manager](https://www.swift.org/documentation/package-manager/)-ის გამოყენებით.

> [!NOTE]
> **SwiftPM, როგორც დამოკიდებულებების ამომცნობი**
>
> Tuist-ის რეკომენდებული მიდგომა დამოკიდებულებების მიმართ იყენებს Swift Package Manager-ს (SPM) მხოლოდ დამოკიდებულებების ამოსაცნობად. Tuist შემდეგ გარდაქმნის მათ Xcode პროექტებად და target-ებად მაქსიმალური კონფიგურირებადობისა და კონტროლისთვის.


## ვიზუალიზაცია პროექტის {#visualize-the-project}

შეგიძლიათ ვიზუალიზაცია გაუკეთოთ პროექტის სტრუქტურას შემდეგი ბრძანების გაშვებით:

```bash
tuist graph
```

ბრძანება შექმნის და გახსნის `graph.png` ფაილს პროექტის დირექტორიაში:

![პროექტის გრაფი](/images/guides/quick-start/graph.png)

## გამოიყენეთ დამოკიდებულება {#use-the-dependency}

გაუშვით `tuist generate`, რათა გახსნათ პროექტი Xcode-ში და შეიტანეთ შემდეგი ცვლილებები `ContentView.swift` ფაილში:

```swift
import SwiftUI
import Kingfisher

public struct ContentView: View {
    public init() {}

    public var body: some View {
        KFImage(URL(string: "https://tuist.dev/images/tuist_logo_32x32@2x.png")!)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

გაუშვით აპლიკაცია Xcode-დან და უნდა დაინახოთ სურათი, რომელიც ჩაიტვირთა URL-დან.
