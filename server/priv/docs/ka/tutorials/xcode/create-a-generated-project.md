---
{
  "title": "გენერირებული პროექტის შექმნა",
  "titleTemplate": ":title · Xcode · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ თქვენი პირველი Tuist-ით გენერირებული Xcode პროექტი და დაამატოთ მას დამოკიდებულებები"
}
---
# შექმენით გენერირებული პროექტი {#create-a-generated-project}

ყველაზე მარტივი გზა Tuist-ის დასაწყებად ნებისმიერ დირექტორიაში ან არსებული პროექტის დირექტორიაში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება გაგივლით ნაბიჯებს <.localized_link href="/guides/features/projects">გენერირებული პროექტის შესაქმნელად</.localized_link> ან არსებული Xcode პროექტის ან სამუშაო სივრცის ინტეგრაციისთვის. ის გეხმარებათ თქვენი გარემოს დაკავშირებაში დისტანციურ სერვერთან, რაც საშუალებას გაძლევთ მიიღოთ წვდომა ისეთ ფუნქციებზე, როგორიცაა <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირება</.localized_link>, <.localized_link href="/guides/features/previews">პრივიუები</.localized_link> და <.localized_link href="/guides/features/package-registries/swift">რეესტრი</.localized_link>.

> [!NOTE]
> **არსებული პროექტის მიგრაცია**
>
> თუ გსურთ არსებული პროექტის მიგრაცია გენერირებულ პროექტებზე დეველოპერული გამოცდილების გასაუმჯობესებლად და ჩვენი <.localized_link href="/guides/features/cache">ქეშის</.localized_link> გამოსაყენებლად, იხილეთ ჩვენი <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">მიგრაციის სახელმძღვანელო</.localized_link>.


## დამატეთ დამოკიდებულებები {#add-dependencies}

ხშირია, რომ პროექტები ეყრდნობიან მესამე მხარის ბიბლიოთეკებს დამატებითი ფუნქციონალის უზრუნველსაყოფად. ამისათვის, გაუშვით შემდეგი ბრძანება პროექტის რედაქტირების საუკეთესო გამოცდილების მისაღებად:

```bash
tuist edit
```

გაიხსნება Xcode პროექტი, რომელიც შეიცავს თქვენს პროექტის ფაილებს. ჩაასწორეთ `Package.swift` და დაამატეთ

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

შემდეგ ჩაასწორეთ თქვენი პროექტის აპლიკაციის სამიზნე (target), რათა განაცხადოთ `Kingfisher` როგორც დამოკიდებულება:

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
                .external(name: "Kingfisher") // [!code ++]
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

შემდეგ გაუშვით `tuist install` დამოკიდებულებების გადასაჭრელად და ჩამოსატვირთად [Swift Package Manager](https://www.swift.org/documentation/package-manager/)-ის გამოყენებით.

> [!NOTE]
> **SPM როგორც დამოკიდებულებების ამომხსნელი**
>
> Tuist-ის რეკომენდებული მიდგომა დამოკიდებულებების მიმართ იყენებს Swift Package Manager-ს (SPM) მხოლოდ დამოკიდებულებების გადასაჭრელად. Tuist შემდეგ გარდაქმნის მათ Xcode პროექტებად და სამიზნეებად მაქსიმალური კონფიგურირებადობისა და კონტროლისთვის.


## ვიზუალიზაცია პროექტის {#visualize-the-project}

შეგიძლიათ ვიზუალიზაცია გაუკეთოთ პროექტის სტრუქტურას შემდეგი ბრძანების გაშვებით:

```bash
tuist graph
```

ბრძანება შექმნის და გახსნის `graph.png` ფაილს პროექტის დირექტორიაში:

![პროექტის გრაფი](/images/guides/quick-start/graph.png)

## გამოიყენეთ დამოკიდებულება {#use-the-dependency}

გაუშვით `tuist generate` პროექტის Xcode-ში გასახსნელად და შეიტანეთ შემდეგი ცვლილებები `ContentView.swift` ფაილში:

```swift
import SwiftUI
import Kingfisher // [!code ++]

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("Hello, World!") // [!code --]
            .padding() // [!code --]
        KFImage(URL(string: "https://cloud.tuist.io/images/tuist_logo_32x32@2x.png")!) // [!code ++]
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

გაუშვით აპლიკაცია Xcode-დან და თქვენ უნდა დაინახოთ სურათი, რომელიც ჩაიტვირთა URL-დან.
