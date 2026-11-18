---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ განაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ხშირად მას რამდენიმე სამიზნედ (target) ყოფენ კოდის გასაზიარებლად, საზღვრების დასადგენად და ბილდის დროის შესამცირებლად. რამდენიმე სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულებების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის დიზაინის გამო, დამოკიდებულებების გრაფის შენარჩუნება შეიძლება იყოს მოსაწყენი და შეცდომებისკენ მიდრეკილი ამოცანა. აქ არის რამდენიმე მაგალითი პრობლემებისა, რომლებიც შეიძლება წააწყდეთ:

- რადგან Xcode-ის ბილდის სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე დირექტორიაში ათავსებს derived data-ში, სამიზნეებს შეიძლება ჰქონდეთ იმპორტის საშუალება ისეთი პროდუქტების, რომლებიც არ უნდა იმპორტირდეს. კომპილაციები შეიძლება ჩაიშალოს CI-ზე, სადაც სუფთა ბილდები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს ნებისმიერ დირექტორიაში, რომელიც შედის `LD_RUNPATH_SEARCH_PATHS` ბილდის პარამეტრში. თუ ეს არ გაკეთდა, სამიზნე ვერ იპოვის მათ შესრულების დროს. ეს ადვილად გასააზრებელი და დასაყენებელია, როცა გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, სამიზნეს სჭირდება დამატებითი ბილდის ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს სწორი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს ბილდის ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ ჩამოთვლილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრი სხვაც წაგვყდომია. წარმოიდგინეთ, თუ დამოკიდებულებების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად ინჟინრების გუნდი დაგჭირდებოდათ. ან კიდევ უარესი, რომ სირთულეებს ბილდის დროს გადაწყვეტდა დახურული კოდის მქონე ბილდის სისტემა, რომლის კონტროლი ან მორგება შეუძლებელია. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მ აირჩია Xcode-ისა და XcodeProj-ის შემთხვევაში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ ვთვლით, რომ დამოკიდებულებების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ასე შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, დანარჩენს კი ჩვენ ვაკეთებთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაგირებულია.

შემდეგ სექციებში ისწავლით, როგორ გამოაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ამოწმებს გრაფს პროექტის გენერაციისას, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულებების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებული იმავე ან სხვა პროექტების სხვა სამიზნეებზე, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი ნებისმიერი შემდეგი ვარიანტით:

- `Target`: აცხადებს დამოკიდებულებას იმავე პროექტში არსებულ სამიზნესთან.
- `Project`: აცხადებს დამოკიდებულებას სხვა პროექტში არსებულ სამიზნესთან.
- `Framework`: აცხადებს დამოკიდებულებას ბინარულ ფრეიმვორკთან.
- `Library`: აცხადებს დამოკიდებულებას ბინარულ ბიბლიოთეკასთან.
- `XCFramework`: აცხადებს დამოკიდებულებას ბინარულ XCFramework-თან.
- `SDK`: აცხადებს დამოკიდებულებას სისტემურ SDK-თან.
- `XCTest`: აცხადებს დამოკიდებულებას XCTest-თან.
- `Macro`: აცხადებს დამოკიდებულებას იმავე პროექტში განსაზღვრულ Swift macro სამიზნესთან (იხილეთ [Swift Macros](#swift-macros)).

> [!NOTE]
> **დამოკიდებულების პირობები**
>
> ყველა ტიპის დამოკიდებულება იღებს `condition` ოფციას, რათა პლატფორმის მიხედვით პირობითად დააკავშიროს დამოკიდებულება. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარდაჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას, გამოაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების გამოსაცხადებლად. Tuist იყენებს Swift Package Manager-ს მათ ამოსახსნელად; იმის შესახებ, თუ როგორ შეედრება ლოკალური პაკეტებით მოდულარიზაცია Tuist პროექტს, იხილეთ [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager). მათი ინტეგრირება შეგიძლიათ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, არ აქვს ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახავად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ, ინტეგრირება გაუკეთოთ Swift Packages-ს თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ ვხდით მას თავსებად ისეთ სამუშაო ნაკადებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას სავარაუდოდ უფრო მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციის დასამუშავებლად. თუმცა, მაპინგის ლოგიკა Swift Packages-სა და XcodeProj სამიზნეებს შორის ღია კოდის მქონეა და საზოგადოებას შეუძლია შეიტანოს მასში წვლილი. ეს საპირისპიროა Xcode-ის ნაგულისხმევი ინტეგრაციისა, რომელიც დახურული კოდის მქონეა და Apple-ის მიერ მხარდაჭერილი.

გარე დამოკიდებულებების დასამატებლად, უნდა შექმნათ `Package.swift` ან `Tuist/`-ის ქვეშ, ან პროექტის ფესვში.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

> [!TIP]
> **პაკეტის პარამეტრები**
>
> `PackageSettings` ინსტანსი, რომელიც გახვეულია კომპილატორის დირექტივაში, საშუალებას გაძლევთ, დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრაცია. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ უნდა დაგჭირდეთ. ასევე შეგიძლიათ გამოიყენოთ იგი SwiftPM ბინარული სამიზნეების მოსალოდნელი ხელმოწერების კონფიგურირებისთვის `expectedSignatures`-ის მეშვეობით.


### ბინარული სამიზნის ხელმოწერები

თუ ლოკალური ან დაშორებული Swift პაკეტი ავლენს ბინარულ XCFramework სამიზნეს, შეგიძლიათ დააკონფიგურიროთ მისი მოსალოდნელი ხელმოწერა `PackageSettings.expectedSignatures`-ის გამოყენებით:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> თუ თქვენი პროექტი იყენებს მორგებულ ბილდის კონფიგურაციებს (ნაგულისხმევი `Debug` და `Release`-ს გარდა), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ცოდნა თქვენი პროექტის კონფიგურაციების შესახებ სწორად ბილდისთვის. მაგალითად:
>
> ```swift
> #if TUIST
>     import ProjectDescription
>
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
>
> მეტი დეტალისთვის იხილეთ [#8345](https://github.com/tuist/tuist/issues/8345).

`Package.swift` ფაილი არის მხოლოდ ინტერფეისი გარე დამოკიდებულებების გამოსაცხადებლად, არაფერი მეტი. ამიტომ პაკეტში არ განსაზღვრავთ არცერთ სამიზნეს ან პროდუქტს. ერთხელ როცა დამოკიდებულებები განსაზღვრული გაქვთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების ამოსახსნელად და `Tuist/Dependencies` დირექტორიაში ჩასატანად:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების ამოხსნა ცალკე ბრძანებაა. ეს მომხმარებელს აძლევს კონტროლს იმაზე, თუ როდის სურს დამოკიდებულებების ამოხსნა და განახლება, და საშუალებას აძლევს გახსნას პროექტი Xcode-ში ისე, რომ ის მზად იყოს კომპილაციისთვის. ჩვენი აზრით, ეს არის ის სფერო, სადაც Apple-ის Swift Package Manager-თან ინტეგრაციით შექმნილი დეველოპერული გამოცდილება დროთა განმავლობაში უარესდება, რაც პროექტი იზრდება.

თქვენი პროექტის სამიზნეებიდან შეგიძლიათ მიმართოთ ამ დამოკიდებულებებს `TargetDependency.external` დამოკიდებულების ტიპის გამოყენებით:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **გარე პაკეტებისთვის სქემები არ გენერირდება**
>
> **სქემები** არ იქმნება ავტომატურად Swift Package პროექტებისთვის, რათა სქემების სია სუფთა დარჩეს. შეგიძლიათ შექმნათ ისინი Xcode-ის UI-ის მეშვეობით.


#### Xcode-ის ნაგულისხმევი ინტეგრაცია {#xcodes-default-integration}

თუ გსურთ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმის გამოყენება, შეგიძლიათ გადასცეთ სია `packages` პროექტის ინსტანციაციისას:

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

და შემდეგ მიმართეთ მათ თქვენი სამიზნეებიდან:

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

როდესაც აერთიანებთ Swift Macro-ს ან Build Tool Plugin-ს გარე Swift Package-დან Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, გამოაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების მოხმარება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ განსაზღვროთ საკუთარი Swift macro პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM build tool plugins**
>
> SPM build tool plugins უნდა გამოცხადდეს [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ, რათა აღმოაჩინონ კონკრეტული ბილდის ბრძანებები, რომლებიც უნდა შესრულდეს სამიზნისთვის. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, ამოხსნილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ გამოცხადებულ გამომავალ მონაცემებზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც უნდა გახდნენ იმავე სამიზნის ბილდის ნაწილი.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია ასახავს პაკეტის პროდუქტებს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ებს არ აქვთ ექვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინი საბოლოოდ შეიძლება შეასრულოს შესრულებადი ფაილი, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის ბილდის ფაზიდან გამოძახება არ არის იგივე, რაც პლაგინის გაშვება: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღადგინოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, მოდელირება გაუკეთოს გამოცხადებულ შეყვანებსა და გამომავალ მონაცემებს და დაამატოს ნებისმიერი გენერირებული ფაილი სამიზნის გრაფში, სანამ Xcode დაგეგმავს ბილდს.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში გამოცხადება და მისი `.external(name:)`-ის მეშვეობით მოხმარება არ არის მხარდაჭერილი. მხარდაჭერილი ალტერნატივაა პაკეტის გამოცხადება `Project.packages`-ში და პლაგინის პროდუქტის დამატება მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ის გამოყენებით. ეს ინარჩუნებს პლაგინს მიბმულს გენერირებულ Xcode პროექტთან, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლოს მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode ხსნის და აწყობს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი ჩნდება გენერირებულ პროექტში, როგორც Swift Package მითითება Tuist-ის მიერ გენერირებული გარე სამიზნის ნაცვლად.
- Tuist ვერ აძლევს პლაგინს იმავე დონის კონტროლს, ვალიდაციას, ქეშირებას და შერჩევითი ტესტირების ქცევას, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურმა ბილდებმა უნდა დაუშვან Xcode-ის პაკეტის ამოხსნა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. როდესაც შესაძლებელია, უპირატესობა მიანიჭეთ სამიზნეში გამოცხადებულ ბილდის ფაზის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ გამოიძახებთ Tuist-ს ან Xcode-ს.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ ბილდის ფაზის დროს. იმისთვის, რომ გენერირდეს Xcode პროექტი build tool plugin-ით, გამოაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

ვინაიდან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update`, რათა გამოიტანოთ დამოკიდებულებები `Carthage/Build` დირექტორიაში და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების გამოცხადებისთვის. შეგიძლიათ ეს გააერთიანოთ სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერაციამდე.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **Build და test**
>
> თუ თქვენს პროექტს აწყობთ და ტესტავთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე უნდა დარწმუნდეთ, რომ Carthage-ის მიერ ამოხსნილი დამოკიდებულებები არსებობს `carthage update` ბრძანების გაშვებით ბილდის ან ტესტირების წინ.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ელის Xcode პროექტს დამოკიდებულებების ინტეგრირებისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერირებისთვის და შემდეგ გაუშვათ `pod install`, რათა ინტეგრირდეს დამოკიდებულებები workspace-ის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს გააერთიანოთ სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერაციამდე.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერაციისთანავე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან fingerprinting ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

არსებობს ორი განსხვავებული სცენარი [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას Tuist პროექტში და ღირს იმის ზუსტად მითითება, თუ რომელში ხართ:

- **გარე Swift Package-ში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი უჭერს მხარს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) შემთხვევაში, თქვენ აცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ის მეშვეობით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნეში. [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) შემთხვევაში, თქვენ აცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. build tool plugins-ისგან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, monorepo-ში არსებულ საერთო ბიბლიოთეკაში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, ასე რომ შეგიძლიათ მაკროს სამიზნე პირდაპირ თქვენს მანიფესტებში განაცხადოთ.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად აღწერს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში Swift Macro სამიზნის ტიპს არ აჩენს, Tuist მას საშუალებას აძლევს ბრძანების სტრიქონის ხელსაწყოს სამიზნის გენერირებით, მისი მაკროს მომხმარებელი სამიზნეების დამოკიდებულებად მიბმით და `-load-plugin-executable` ფლაგის მათ Swift კომპილატორის პარამეტრებში ჩასმით. ეს ყველაფერი თქვენთვის ავტომატურად სრულდება.

ტიპური მაკრო იყოფა ორ სამიზნედ: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც აცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. რადგან პლაგინი build მანქანაზე მუშაობს, მისი სამიზნე მხოლოდ host-ზეა (macOS).

მაკროს იმპლემენტაცია ეყრდნობა [swift-syntax](https://github.com/swiftlang/swift-syntax)-ს, რომელსაც თქვენ აცხადებთ როგორც ჩვეულებრივ გარე დამოკიდებულებას `Tuist/Package.swift`-ში:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

შემდეგ შეგიძლიათ მაკროს პლაგინისა და ბიბლიოთეკის სამიზნეები პირდაპირ თქვენს პროექტში განსაზღვროთ:

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

ნებისმიერ სამიზნეს, რომელიც აკავშირებს `MyLibrary`-ს, ახლა შეუძლია მაკროს გამოყენება — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა მისი ჩატვირთვა შეძლოს.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები და ბიბლიოთეკები შეიძლება იყოს დაკავშირებული სტატიკურად ან დინამიურად, **რაც მნიშვნელოვან გავლენას ახდენს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და გაშვების დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად მიიღება ყოველგვარი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ release აწყობებში რაც შეიძლება მეტი რამ უნდა იყოს სტატიკურად დაკავშირებული სწრაფი გაშვების დროის მისაღწევად, ხოლო debug აწყობებში რაც შეიძლება მეტი რამ უნდა იყოს დინამიურად დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების სირთულე იმაში მდგომარეობს, რომ Xcode-ში ეს არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ რესურსების შენახვა, სტატიკურ ჩარჩოებს ჩაშენება არ სჭირდებათ). Apple-მა სცადა პრობლემის გადაჭრა კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ამატებს ახალ დინამიურ ცვლადებს, რაც ზრდის არადეტერმინიზმის წყაროებს და შესაძლოა გამოიწვიოს ისეთი ფუნქციების, როგორიცაა Swift Previews, რომლებიც კომპილაციის გრაფზეა დამოკიდებული, არასანდოობა.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურ შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ებს, რომლებიც სტანდარტულია დაკავშირების ყველა ტიპისთვის. <.localized_link href="/guides/features/projects/dynamic-configuration">დინამიური კონფიგურაციების გარემოს ცვლადების მეშვეობით</.localized_link> კომბინაციაში, შეგიძლიათ დაკავშირების ტიპი გადასცეთ გამოძახების დროს და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში სამიზნეების პროდუქტის ტიპის დასაყენებლად.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ იყენებს ნაგულისხმევად მოხერხებულობას არაცხადი კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი აწყობის პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` linker ფლაგი](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა დარწმუნდეთ, რომ მიღებული ბინარები სწორია. შესაბამისად, ჩვენი მიდგომაა მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა სწორი გადაწყვეტილებები მიიღოთ.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift Package, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). მეტი დეტალი იხილეთ [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული სია სცენარებისა, სადაც შესაძლოა დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** რადგან აპლიკაციებს და მათ გაფართოებებს კოდის გაზიარება სჭირდებათ, შესაძლოა დაგჭირდეთ იმ სამიზნეების დინამიურად გახდა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ასევე გაფართოებაში, რაც ბინარის ზომას გაზრდის.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ მოწოდებული გაქვთ წინასწარ კომპილირებული ბინარები, რომლებიც სტატიკური ან დინამიურია. სტატიკური ბინარები შეიძლება ჩაისვას დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დაკავშირებისთვის.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება განკუთვნილია იმ პრობლემების იდენტიფიცირებისთვის, რომლებიც შეიძლება წარმოიშვას სტატიკურად დაკავშირებული სამიზნისგან, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება ბინარის ზომის ზრდით ან, უარეს შემთხვევაში, runtime კრაშებით.

## პრობლემების მოგვარება {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრაციისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების ჩართვა შეიძლება საჭირო იყოს runtime კრაშების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

რადგან აწყობის სისტემას და Tuist-ს არ აქვს იმის დადგენის საშუალება, ფლაგი საჭიროა თუ არა, და რადგან ფლაგს შესაძლოა არასასურველი გვერდითი ეფექტები აქვს, Tuist არ გამოიყენებს ამ ფლაგებს ავტომატურად, და რადგან Swift Package Manager `-ObjC`-ს განიხილავს როგორც `.unsafeFlag`-ის მეშვეობით ჩასმულს, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როცა ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როცა საჭიროა, `OTHER_LDFLAGS`-ის დაყენებით მომხმარებელ სამიზნეებზე.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად სიმძლავრისა — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკებს აწყობის პროცესში.

აქ არის რამდენიმე რჩევა, რომლის დაცვაც შეიძლება საჭირო იყოს Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დაემატა `OTHER_LDFLAGS`-ს {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბიბლიოთეკების უმეტესობა დაწერილია Objective-C-ზე. ამის გამო, ნებისმიერ მომხმარებელ სამიზნეს უნდა ჰქონდეს `-ObjC` თეგი მის `OTHER_LDFLAGS` აწყობის პარამეტრში. ეს შეიძლება დაყენდეს `.xcconfig` ფაილში ან ხელით მიეთითოს სამიზნის პარამეტრებში თქვენს Tuist მანიფესტებში. მაგალითი:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

დამატებითი დეტალებისთვის იხილეთ ზემოთ მოცემული [Objective-C დამოკიდებულებები](#objectivec-dependencies) განყოფილება.

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის როგორც დინამიური ჩარჩო {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Google-ის გარკვეული ბიბლიოთეკები დამოკიდებულია `FBLPromises`-ზე, Google-ის კიდევ ერთ ბიბლიოთეკაზე. შეიძლება წააწყდეთ კრაშს, რომელიც მოიცავს `FBLPromises`-ს და გამოიყურება დაახლოებით ასე:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises`-ის პროდუქტის ტიპის `.framework`-ად ცალსახად დაყენება თქვენს `Package.swift` ფაილში უნდა გადაჭრას პრობლემა:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### The Composable Architecture {#the-composable-architecture}

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავობის აღმოფხვრის](#troubleshooting) განყოფილებაში, პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) უნდა დააყენოთ `OTHER_LDFLAGS` აწყობის პარამეტრი `$(inherited) -ObjC`-ზე. ალტერნატიულად, შეგიძლიათ გადააწყოთ პაკეტის პროდუქტის ტიპი დინამიურად. სტატიკური დაკავშირებისას ტესტის და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI პრევიუები არ მუშაობს. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხაფანგები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დააკავშირებს დინამიურად — შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI პრევიუები იმუშავებს.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება არ არის ყოველთვის რეკომენდებული. იხილეთ განყოფილება [სტატიკური თუ დინამიური](#static-or-dynamic) დამატებითი დეტალებისთვის. ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დაკავშირებულია დინამიურად პირობების გარეშე.


```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

> [!WARNING]
> `import Sharing`-ის ნაცვლად უნდა გამოიყენოთ `import SwiftSharing`.


### ტრანზიტული სტატიკური დამოკიდებულებების გაჟონვა `.swiftmodule`-ის მეშვეობით {#transitive-static-dependencies-leaking-through-swiftmodule}

როდესაც დინამიური ჩარჩო ან ბიბლიოთეკა დამოკიდებულია სტატიკურებზე `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ჩარჩოს ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">კომპილაციის შეცდომა გამოიწვიოს</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტზე წვდომის დონე ჩართულია Swift 6-ში. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```

## დაკავშირებული {#related}

წაიკითხეთ [როგორ მიიღო monday.com-მა მოდულარული პროექტის გრაფი Tuist-ით](https://tuist.dev/customers/monday), დაწყებული იმ სამიზნეებით, რომლებსაც ყველაზე ნაკლები დამოკიდებულება აქვთ.
