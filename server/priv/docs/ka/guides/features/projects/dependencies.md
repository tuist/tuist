---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ხშირია მისი რამდენიმე სამიზნედ დაყოფა კოდის გასაზიარებლად, საზღვრების განსასაზღვრად და ბილდის დროის გასაუმჯობესებლად. მრავალი სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულებების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის დიზაინის გამო, დამოკიდებულებების გრაფის შენარჩუნება შეიძლება იყოს შრომატევადი და შეცდომებისკენ მიდრეკილი ამოცანა. აქ არის რამდენიმე მაგალითი პრობლემებისა, რომლებიც შეიძლება შეგხვდეთ:

- რადგან Xcode-ის ბილდის სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე დირექტორიაში ათავსებს წარმოებულ მონაცემებში, სამიზნეებს შეიძლება ჰქონდეთ ისეთი პროდუქტების იმპორტის შესაძლებლობა, რაც არ უნდა ჰქონდეთ. კომპილაციები შეიძლება ჩაიშალოს CI-ზე, სადაც სუფთა ბილდები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს იმ დირექტორიებში, რომლებიც შედიან `LD_RUNPATH_SEARCH_PATHS` ბილდის პარამეტრში. თუ ასე არ მოიქცევით, სამიზნე ვერ იპოვის მათ შესრულების დროს. ეს ადვილია გასააზრებლად და დასაყენებლად, როცა გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, სამიზნეს სჭირდება დამატებითი ბილდის ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს შესაბამისი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს ბილდის ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად გრჩებათ ყურადღების მიღმა.

ზემოთ მოყვანილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრი სხვაც შეგვხვედრია. წარმოიდგინეთ, თუ დამოკიდებულებების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად ინჟინრების გუნდი დაგჭირდებოდათ. ან კიდევ უარესი, რომ სირთულეები ბილდის დროს გადაწყდებოდა დახურული კოდის მქონე ბილდის სისტემით, რომლის კონტროლი ან მორგებაც შეუძლებელია. ნაცნობი ჟღერს? ეს არის მიდგომა, რომელიც Apple-მ აირჩია Xcode-ისა და XcodeProj-ის შემთხვევაში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ გვწამს, რომ დამოკიდებულებების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ასე შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, დანარჩენს კი ჩვენ ვაკეთებთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაქტირებულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ამოწმებს გრაფს პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულებების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებულები ერთსა და იმავე ან სხვა პროექტების სხვა სამიზნეებზე, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი შემდეგი ვარიანტებიდან ნებისმიერით:

- `Target`: აცხადებს დამოკიდებულებას ერთსა და იმავე პროექტში არსებულ სამიზნეზე.
- `Project`: აცხადებს დამოკიდებულებას სხვა პროექტში არსებულ სამიზნეზე.
- `Framework`: აცხადებს დამოკიდებულებას ბინარულ ფრეიმვორკზე.
- `Library`: აცხადებს დამოკიდებულებას ბინარულ ბიბლიოთეკაზე.
- `XCFramework`: აცხადებს დამოკიდებულებას ბინარულ XCFramework-ზე.
- `SDK`: აცხადებს დამოკიდებულებას სისტემურ SDK-ზე.
- `XCTest`: აცხადებს დამოკიდებულებას XCTest-ზე.
- `Macro`: აცხადებს დამოკიდებულებას იმავე პროექტში განსაზღვრულ Swift macro სამიზნეზე (იხილეთ [Swift Macros](#swift-macros)).

> [!NOTE]
> **დამოკიდებულების პირობები**
>
> დამოკიდებულების ყოველი ტიპი იღებს `condition` პარამეტრს დამოკიდებულების პლატფორმის მიხედვით პირობითად დასაკავშირებლად. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარდაუჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. მათი ინტეგრირება შეგიძლიათ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, არ აქვს ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ ინტეგრირება გაუკეთოთ Swift Packages-ს თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ თავსებადს ხდის მას ისეთ სამუშაო ნაკადებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას, სავარაუდოდ, მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციის დასამუშავებლად. თუმცა, Swift Packages-სა და XcodeProj სამიზნეებს შორის მეფინგის ლოგიკა ღია კოდია და საზოგადოებას შეუძლია შეიტანოს წვლილი. ეს განსხვავდება Xcode-ის ნაგულისხმევი ინტეგრაციისგან, რომელიც დახურული კოდია და Apple-ის მიერ ნადგურდება.

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
> `PackageSettings` ინსტანსი, რომელიც კომპილატორის დირექტივაშია გახვეული, საშუალებას გაძლევთ დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრაცია. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ უნდა დაგჭირდეთ. ასევე შეგიძლიათ გამოიყენოთ ის SwiftPM ბინარული სამიზნეების მოსალოდნელი ხელმოწერების დასაკონფიგურირებლად `expectedSignatures`-ის მეშვეობით.


### ბინარული სამიზნის ხელმოწერები

თუ ლოკალური ან დისტანციური Swift პაკეტი ავლენს ბინარულ XCFramework სამიზნეს, შეგიძლიათ დააკონფიგურიროთ მისი მოსალოდნელი ხელმოწერა `PackageSettings.expectedSignatures`-ის გამოყენებით:

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
> თუ თქვენი პროექტი იყენებს მორგებულ ბილდის კონფიგურაციებს (სტანდარტული `Debug` და `Release`-ს გარდა), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ინფორმაცია თქვენი პროექტის კონფიგურაციების შესახებ სწორად ბილდისთვის. მაგალითად:
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

`Package.swift` ფაილი მხოლოდ ინტერფეისია გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომ პაკეტში არ განსაზღვრავთ არცერთ სამიზნეს ან პროდუქტს. როდესაც დამოკიდებულებები განსაზღვრული გაქვთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების გადასაწყვეტად და `Tuist/Dependencies` დირექტორიაში ჩამოსატანად:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გადაწყვეტა ცალკე ბრძანებაა. ეს მომხმარებლებს აძლევს კონტროლს იმაზე, თუ როდის სურთ დამოკიდებულებების გადაწყვეტა და განახლება, და საშუალებას აძლევს გახსნან Xcode პროექტი ისე, რომ ის კომპილაციისთვის მზად იყოს. ეს არის ის სფერო, სადაც ჩვენი აზრით, Apple-ის Swift Package Manager-თან ინტეგრაციით უზრუნველყოფილი დეველოპერული გამოცდილება დროთა განმავლობაში პროექტის ზრდასთან ერთად უარესდება.

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
                .external(name: "Alamofire"), // [!code ++]
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

თუ გსურთ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმის გამოყენება, შეგიძლიათ გადასცეთ სია `packages` პროექტის ინიციალიზაციისას:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

და შემდეგ მიმართეთ მათ თქვენი სამიზნეებიდან:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

გარე Swift პაკეტიდან Swift Macro-ს ან Build Tool Plugin-ის ინტეგრირებისას Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების გამოყენება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ საკუთარი Swift macro-ს განსაზღვრა პაკეტიდან აღების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM Build Tool Plugins**
>
> SPM build tool plugins უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ იმ კონკრეტული ბილდის ბრძანებების აღმოჩენის მიზნით, რომლებიც სამიზნისთვის უნდა შესრულდეს. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გადაწყვეტილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ განცხადებულ გამომავალ მონაცემებზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც უნდა გახდნენ იმავე სამიზნის ბილდის ნაწილი.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია ასახავს პაკეტის პროდუქტებს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ებს არ გააჩნიათ ექვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინს საბოლოოდ შეუძლია შეასრულოს შესრულებადი ფაილი, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის ბილდის ფაზიდან გამოძახება არ არის იგივე, რაც პლაგინის გაშვება: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღწარმოოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, დაამოდელიროს განცხადებული შეყვანები და გამომავალი მონაცემები და დაამატოს ნებისმიერი გენერირებული ფაილი სამიზნის გრაფს, სანამ Xcode დაგეგმავს ბილდს.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განცხადება და მისი `.external(name:)`-ის მეშვეობით გამოყენება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის განცხადება `Project.packages`-ში და პლაგინის პროდუქტის დამატება მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ის გამოყენებით. ეს ინარჩუნებს პლაგინს მიბმულს გენერირებულ Xcode პროექტთან, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლონ მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და ქმნის პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი ჩნდება გენერირებულ პროექტში, როგორც Swift Package მითითება Tuist-ით გენერირებული გარე სამიზნის ნაცვლად.
- Tuist ვერ აძლევს პლაგინს იმავე დონის კონტროლს, ვალიდაციას, ქეშირებას და შერჩევითი ტესტირების ქცევას, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურმა ბილდებმა უნდა დაუშვან Xcode-ის პაკეტის გადაწყვეტა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. შესაძლებლობის შემთხვევაში, უპირატესობა მიანიჭეთ სამიზნეში განცხადებულ ბილდის ფაზის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ Tuist-ს ან Xcode-ს გამოიძახებთ.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ ბილდის ფაზის დროს. Xcode პროექტის გენერირებისთვის build tool plugin-ის შენარჩუნებით, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

ვინაიდან [Carthage](https://github.com/carthage/carthage) აწარმოებს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update` დამოკიდებულებების `Carthage/Build` დირექტორიაში გამოსატანად და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ეს გააერთიანოთ სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერაციამდე.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ბილდი და ტესტი**
>
> თუ თქვენს პროექტს ქმნით და ტესტავთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე უნდა დარწმუნდეთ, რომ Carthage-ით გადაწყვეტილი დამოკიდებულებები არსებობს `carthage update` ბრძანების გაშვებით ბილდის ან ტესტირების წინ.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ელის Xcode პროექტს დამოკიდებულებების ინტეგრირებისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერირებისთვის და შემდეგ გაუშვათ `pod install` დამოკიდებულებების ინტეგრირებისთვის workspace-ის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს გააერთიანოთ სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერაციამდე.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერაციისთანავე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან fingerprinting ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს იმის მკაფიოდ განსაზღვრა, თუ რომელში ხართ:

- **გარე Swift პაკეტში განსაზღვრული მაკროს გამოყენება.** ორივე ინტეგრაციის მექანიზმი მხარს უჭერს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) შემთხვევაში, თქვენ აცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნეში. [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) შემთხვევაში, თქვენ აცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. build tool plugins-ებისგან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, საერთო ბიბლიოთეკაში თქვენს monorepo-ში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, რაც საშუალებას გაძლევთ პირდაპირ მანიფესტებში განაცხადოთ მაკროს სამიზნე.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად აღწერს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში არ წარმოადგენს Swift Macro სამიზნის ტიპს, Tuist საშუალებას იძლევა ამისა ბრძანების ხაზის ინსტრუმენტის სამიზნის გენერირებით, მისი მაკროს მომხმარებელი სამიზნეების დამოკიდებულებად მიბმით და `-load-plugin-executable` ფლაგის შეყვანით მათ Swift კომპილატორის პარამეტრებში. ეს ყველა ტექნიკური დეტალი თქვენთვის სრულდება.

ტიპური მაკრო იყოფა ორ სამიზნედ: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც აცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. ვინაიდან პლაგინი მუშაობს აწყობის მანქანაზე, მისი სამიზნე მხოლოდ host-ისთვისაა (macOS).

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

შემდეგ შეგიძლიათ პირდაპირ თქვენს პროექტში განსაზღვროთ მაკროს პლაგინისა და ბიბლიოთეკის სამიზნეები:

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

ნებისმიერ სამიზნეს, რომელიც უკავშირდება `MyLibrary`-ს, შეუძლია გამოიყენოს მაკრო — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა შეძლოს მისი ჩატვირთვა.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები და ბიბლიოთეკები შეიძლება დაუკავშირდეს სტატიკურად ან დინამიურად, **რაც მნიშვნელოვან გავლენას ახდენს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და ჩატვირთვის დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად მიიღება დიდი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ release აწყობებში რაც შეიძლება მეტი რამ სტატიკურად უნდა იყოს დაკავშირებული სწრაფი ჩატვირთვის დროის მისაღწევად, ხოლო debug აწყობებში რაც შეიძლება მეტი რამ დინამიურად უნდა იყოს დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების სირთულე იმაში მდგომარეობს, რომ Xcode-ში ეს არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ შეიცავდნენ რესურსებს, სტატიკურ ჩარჩოებს არ სჭირდებათ ჩაშენება). Apple ცდილობდა პრობლემის გადაჭრას კომპილაციის დროის გადაწყვეტებით, როგორიცაა Swift Package Manager-ის ავტომატური გადაწყვეტილება სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ამატებს ახალ დინამიურ ცვლადებს, ქმნის არადეტერმინიზმის ახალ წყაროებს და შესაძლოა გამოიწვიოს ისეთი ფუნქციების, როგორიცაა Swift Previews, რომლებიც ეყრდნობიან კომპილაციის გრაფს, არასანდოობას.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურს შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">ბანდლის აქსესორებს</.localized_link>, რომლებიც სტანდარტულია დაკავშირების ყველა ტიპისთვის. <.localized_link href="/guides/features/projects/dynamic-configuration">გარემოს ცვლადების მეშვეობით დინამიური კონფიგურაციების</.localized_link> კომბინაციაში, შეგიძლიათ გადასცეთ დაკავშირების ტიპი გამოძახების დროს და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში სამიზნეების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ იყენებს ნაგულისხმევად მოხერხებულობას არააშკარა კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი აწყობის პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა დარწმუნდეთ, რომ მიღებული ბინარები სწორია. შესაბამისად, ჩვენი მიდგომა არის მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა მიიღოთ სწორი გადაწყვეტილებები.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift პაკეტი, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). იხილეთ მეტი დეტალი [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. შემდეგი არ არის ამომწურავი სია სცენარებისა, სადაც შეიძლება დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** ვინაიდან აპლიკაციებს და მათ გაფართოებებს სჭირდებათ კოდის გაზიარება, შეიძლება დაგჭირდეთ ამ სამიზნეების დინამიურად გახდომა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ისე გაფართოებაში, რაც გაზრდის ბინარულ ზომას.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ მოგეწოდებათ წინასწარ კომპილირებული ბინარები, რომლებიც არის სტატიკური ან დინამიური. სტატიკური ბინარები შეიძლება ჩაისვას დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დასაკავშირებლად.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება განკუთვნილია იმ პრობლემების იდენტიფიცირებისთვის, რომლებიც შეიძლება წარმოიშვას სამიზნის სტატიკურად დაკავშირებისგან, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება როგორც გაზრდილი ბინარული ზომა ან, უარეს შემთხვევებში, runtime crash-ები.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრაციისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების ჩართვა შეიძლება იყოს აუცილებელი runtime crash-ების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

ვინაიდან აწყობის სისტემას და Tuist-ს არ აქვს ფლაგის აუცილებლობის დადგენის გზა, და ვინაიდან ფლაგს შეიძლება ჰქონდეს არასასურველი გვერდითი ეფექტები, Tuist არ გამოიყენებს ამ ფლაგებს ავტომატურად, და ვინაიდან Swift Package Manager `-ObjC`-ს განიხილავს როგორც `.unsafeFlag`-ის მეშვეობით ჩართულს, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როდესაც ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როდესაც ეს საჭიროა, მომხმარებელ სამიზნეებზე `OTHER_LDFLAGS`-ის დაყენებით.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად მათი სიმძლავრის — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკებს აწყობის პროცესში.

აქ არის რამდენიმე რჩევა, რომელთა მიყოლაც შეიძლება იყოს აუცილებელი Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დამატებულია `OTHER_LDFLAGS`-ში {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბიბლიოთეკების უმეტესობა დაწერილია Objective-C-ზე. ამის გამო, ნებისმიერ მომხმარებელ სამიზნეს უნდა ჰქონდეს `-ObjC` ტეგი თავის `OTHER_LDFLAGS` აწყობის პარამეტრში. ეს შეიძლება იყოს მითითებული `.xcconfig` ფაილში ან ხელით განსაზღვრული თქვენი Tuist მანიფესტებში სამიზნის პარამეტრებში. მაგალითი:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

დამატებითი დეტალებისთვის იხილეთ ზემოთ მოცემული [Objective-C დამოკიდებულებები](#objective-c-dependencies) სექცია.

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის დინამიურ ჩარჩოდ {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Google-ის ზოგიერთი ბიბლიოთეკა ეყრდნობა `FBLPromises`-ს, Google-ის კიდევ ერთ ბიბლიოთეკას. შეიძლება წააწყდეთ კრახს, რომელიც ახსენებს `FBLPromises`-ს და გამოიყურება დაახლოებით ასე:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises`-ის პროდუქტის ტიპის ცალსახად `.framework`-ად დაყენება თქვენს `Package.swift` ფაილში უნდა აღმოფხვრას პრობლემა:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავი სიტუაციების გადაჭრის](#troubleshooting) სექციაში, პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) უნდა დააყენოთ `OTHER_LDFLAGS` აწყობის პარამეტრი `$(inherited) -ObjC`-ზე. ალტერნატიულად, შეგიძლიათ გადააწეროთ პაკეტის პროდუქტის ტიპი დინამიურად. სტატიკური დაკავშირებისას ტესტისა და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI გადახედვები არ მუშაობს. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის სირთულეები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დააკავშირებს დინამიურად - შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI გადახედვები იმუშავებს.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება ყოველთვის არ არის რეკომენდებული. იხილეთ სექცია [სტატიკური თუ დინამიური](#static-or-dynamic) დამატებითი დეტალებისთვის. ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დაკავშირებულია დინამიურად პირობების გარეშე.


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

როდესაც დინამიური ფრეიმვორკი ან ბიბლიოთეკა ეყრდნობა სტატიკურებს `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ფრეიმვორკის ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">გამოიწვიოს კომპილაციის შეცდომა</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტზე წვდომის დონე ჩართულია Swift 6-ში. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```
