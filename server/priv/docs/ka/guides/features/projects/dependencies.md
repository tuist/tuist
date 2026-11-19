---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ განაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ჩვეულებრივია მისი რამდენიმე მიზნად (target) დაყოფა კოდის გასაზიარებლად, საზღვრების განსასაზღვრად და ბილდის დროის გასაუმჯობესებლად. რამდენიმე მიზანი ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულებების გრაფს**, რომელიც შეიძლება ასევე მოიცავდეს გარე დამოკიდებულებებს.

## XcodeProj-ით კოდიფიცირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის დიზაინის გამო, დამოკიდებულებების გრაფის შენარჩუნება შეიძლება იყოს მოსაწყენი და შეცდომებისკენ მიდრეკილი ამოცანა. აქ არის რამდენიმე მაგალითი პრობლემებისა, რომლებიც შეიძლება წააწყდეთ:

- რადგან Xcode-ის ბილდის სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე დირექტორიაში ათავსებს derived data-ში, მიზნებმა შესაძლოა შეძლონ ისეთი პროდუქტების იმპორტი, რაც არ უნდა შეეძლოთ. კომპილაციები შეიძლება ჩავარდეს CI-ზე, სადაც სუფთა ბილდები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- მიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს ნებისმიერ დირექტორიაში, რომელიც შედის `LD_RUNPATH_SEARCH_PATHS` ბილდის პარამეტრში. თუ ეს არ მოხდება, მიზანი ვერ შეძლებს მათ პოვნას შესრულების დროს. ეს ადვილად გასააზრებელი და დასაყენებელია, როცა გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც მიზანი აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, მიზანს სჭირდება დამატებითი ბილდის ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს შესაბამისი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს ბილდის ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ მოყვანილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრად მეტი შეგვხვედრია. წარმოიდგინეთ, რომ გჭირდებოდათ ინჟინრების გუნდი დამოკიდებულებების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად. ან კიდევ უარესი, რომ სირთულეები ბილდის დროს წყდებოდა დახურული კოდის ბილდის სისტემით, რომელსაც ვერ აკონტროლებთ ან ვერ ადაპტირებთ. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მ აირჩია Xcode-ისა და XcodeProj-ისთვის და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

მტკიცედ ვფიქრობთ, რომ დამოკიდებულებების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ამ შემთხვევაში შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, დანარჩენზე კი ჩვენ ვზრუნავთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაქტულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ამოწმებს გრაფს პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულებების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

მიზნებს შეუძლიათ იყვნენ დამოკიდებულებში სხვა მიზნებზე იმავე და სხვა პროექტებში, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი ნებისმიერი შემდეგი ვარიანტით:

- `Target`: აცხადებს დამოკიდებულებას იმავე პროექტში არსებულ მიზანთან.
- `Project`: აცხადებს დამოკიდებულებას სხვა პროექტში არსებულ მიზანთან.
- `Framework`: აცხადებს დამოკიდებულებას ბინარულ ფრეიმვორკთან.
- `Library`: აცხადებს დამოკიდებულებას ბინარულ ბიბლიოთეკასთან.
- `XCFramework`: აცხადებს დამოკიდებულებას ბინარულ XCFramework-თან.
- `SDK`: აცხადებს დამოკიდებულებას სისტემურ SDK-თან.
- `XCTest`: აცხადებს დამოკიდებულებას XCTest-თან.
- `Macro`: აცხადებს დამოკიდებულებას Swift macro მიზანთან, რომელიც განსაზღვრულია იმავე პროექტში (იხილეთ [Swift Macros](#swift-macros)).

> [!NOTE]
> **დამოკიდებულების პირობები**
>
> ყველა ტიპის დამოკიდებულება იღებს `condition` პარამეტრს დამოკიდებულების პლატფორმის მიხედვით პირობითად დასაკავშირებლად. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც მიზანი მხარს უჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. Tuist იყენებს Swift Package Manager-ს მათ გასაწყვეტად; იმის შესახებ, თუ როგორ შედარდება მოდულარიზაცია ლოკალური პაკეტებით Tuist-ის პროექტთან, იხილეთ [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager). შეგიძლიათ მათი ინტეგრირება Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, არ აქვს ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ ინტეგრირება მოახდინოთ Swift Packages-ის თქვენს პროექტში XcodeProj-ის მიზნების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ თავსებადს ხდის მას ისეთ სამუშაო ნაკადებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას სავარაუდოდ მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციების დასამუშავებლად. თუმცა, მაპინგის ლოგიკა Swift Packages-სა და XcodeProj-ის მიზნებს შორის ღია კოდია და საზოგადოებამ შეიძლება შეიტანოს მასში წვლილი. ეს ეწინააღმდეგება Xcode-ის ნაგულისხმევ ინტეგრაციას, რომელიც დახურული კოდია და Apple-ის მიერ ნადგურდება.

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
> `PackageSettings` ინსტანსი, რომელიც გახვეულია კომპილატორის დირექტივაში, საშუალებას გაძლევთ დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრაცია. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის გამოყენებული ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ უნდა დაგჭირდეთ. ასევე შეგიძლიათ გამოიყენოთ იგი SwiftPM ბინარული მიზნების მოსალოდნელი ხელმოწერების დასაკონფიგურირებლად `expectedSignatures`-ის მეშვეობით.


### ბინარული მიზნის ხელმოწერები

თუ ლოკალური ან დაშორებული Swift პაკეტი ავლენს ბინარულ XCFramework მიზანს, შეგიძლიათ დააკონფიგურიროთ მისი მოსალოდნელი ხელმოწერა `PackageSettings.expectedSignatures`-ის გამოყენებით:

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
> თუ თქვენი პროექტი იყენებს მორგებულ ბილდის კონფიგურაციებს (კონფიგურაციები, რომლებიც განსხვავდება სტანდარტული `Debug` და `Release`-გან), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ცოდნა თქვენი პროექტის კონფიგურაციების შესახებ სწორად ბილდისთვის. მაგალითად:
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
> იხილეთ [#8345](https://github.com/tuist/tuist/issues/8345) დეტალებისთვის.

`Package.swift` ფაილი არის მხოლოდ ინტერფეისი გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომ არ განსაზღვრავთ არცერთ მიზანს ან პროდუქტს პაკეტში. ერთხელ როცა დამოკიდებულებები განსაზღვრული გაქვთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების გასაწყვეტად და `Tuist/Dependencies` დირექტორიაში ჩამოსატანად:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გაწყვეტა ცალკე ბრძანებით ხდება. ეს მომხმარებელს აძლევს კონტროლს იმაზე, თუ როდის სურს დამოკიდებულებების გაწყვეტა და განახლება, და საშუალებას აძლევს პროექტი Xcode-ში გახსნას ისე, რომ ის კომპილაციისთვის მზად იყოს. ეს არის ის სფერო, სადაც ჩვენი აზრით, Apple-ის Swift Package Manager-თან ინტეგრაციით შექმნილი დეველოპერული გამოცდილება პროექტის ზრდასთან ერთად უარესდება.

თქვენი პროექტის მიზნებიდან შეგიძლიათ ამ დამოკიდებულებებზე მიუთითოთ `TargetDependency.external` დამოკიდებულების ტიპის გამოყენებით:

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
> **სქემები** ავტომატურად არ იქმნება Swift Package პროექტებისთვის, რათა სქემების სია სუფთა დარჩეს. მათი შექმნა Xcode-ის UI-ით შეგიძლიათ.


#### Xcode-ის ნაგულისხმევი ინტეგრაცია {#xcodes-default-integration}

თუ გსურთ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმის გამოყენება, პროექტის შექმნისას შეგიძლიათ გადასცეთ სია `packages`:

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

შემდეგ კი თქვენი მიზნებიდან მათზე მიუთითეთ:

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

როდესაც გარე Swift პაკეტიდან Swift Macro-ს ან Build Tool Plugin-ს Xcode-ის ნაგულისხმევი ინტეგრაციით აერთიანებთ, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების მოხმარება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით](#tuists-xcodeprojbased-integration), ხოლო თუ გსურთ საკუთარი Swift მაკროს განსაზღვრა პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM ბილდის ხელსაწყოების პლაგინები**
>
> SPM ბილდის ხელსაწყოების პლაგინები უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration) იყენებთ.

SPM ბილდის ხელსაწყოების პლაგინები არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ, რათა აღმოაჩინონ კონკრეტული ბილდის ბრძანებები, რომლებიც მიზნისთვის უნდა შესრულდეს. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, მიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გაწყვეტილ პლაგინის ხელსაწყოებზე და პლაგინის მიერ განცხადებულ გამოსავალზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც იმავე მიზნის ბილდის ნაწილი უნდა გახდეს.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია პაკეტის პროდუქტებს ნატიურ Xcode მიზნებში ასახავს, როდესაც ასახვა სტატიკურია, მაგალითად ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. ბილდის ხელსაწყოების პლაგინებს არ აქვთ ექვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინი საბოლოოდ შეიძლება შეასრულოს შესრულებადი ფაილი, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის ბილდის ფაზიდან გამოძახება არ არის პლაგინის გაშვების ექვივალენტი: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღადგინოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, დაამოდელირებს განცხადებულ შეყვანებსა და გამოსავალს და დაამატოს ნებისმიერი გენერირებული ფაილი მიზნის გრაფში, სანამ Xcode ბილდს დაგეგმავს.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განცხადება და მისი `.external(name:)`-ით მოხმარება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის `Project.packages`-ში განცხადება და პლაგინის პროდუქტის მომხმარებელ მიზანში `.package(product:type: .plugin)`-ით დამატება. ეს პლაგინს გენერირებულ Xcode პროექტთან Swift Package პროდუქტის დამოკიდებულებად აკავშირებს, რათა Xcode-მა და SwiftPM-მა ის ნატიური პლაგინის კონტექსტით შეასრულონ.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და აგებს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციით.
- პაკეტი გენერირებულ პროექტში ჩანს როგორც Swift Package მითითება Tuist-ით გენერირებული გარე მიზნის ნაცვლად.
- Tuist ვერ აძლევს პლაგინს იმავე დონის კონტროლს, ვალიდაციას, ქეშირებას და შერჩევითი ტესტირების ქცევას, რასაც ის სტატიკურად ასახულ პაკეტის პროდუქტებს სთავაზობს.
- CI და ლოკალურმა ბილდებმა უნდა დაუშვან Xcode-ის პაკეტის გაწყვეტა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM ბილდის ხელსაწყოების პლაგინების გამოყენებას Tuist პროექტებში. როდესაც შესაძლებელია, უპირატესობა მიანიჭეთ მიზანში განცხადებულ ბილდის ფაზის სკრიპტს, ან გაუშვით ხელსაწყო სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ Tuist-ს ან Xcode-ს გამოიძახებთ.

SPM ბილდის ხელსაწყოების პლაგინის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ ბილდის ფაზის დროს. Xcode პროექტის ბილდის ხელსაწყოების პლაგინით გენერირებისთვის, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` მიზნის დამოკიდებულებებში.

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

ვინაიდან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update`, რათა დამოკიდებულებები `Carthage/Build` დირექტორიაში გამოიტანოთ და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` მიზნის დამოკიდებულების ტიპი თქვენს მიზანში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ბილდი და ტესტი**
>
> თუ თქვენს პროექტს `xcodebuild build` და `tuist test`-ით აგებთ და ტესტავთ, ანალოგიურად უნდა დარწმუნდეთ, რომ Carthage-ით გაწყვეტილი დამოკიდებულებები არსებობს `carthage update` ბრძანების გაშვებით ბილდის ან ტესტირების წინ.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ელის Xcode პროექტს დამოკიდებულებების ინტეგრირებისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერირებისთვის და შემდეგ გაუშვათ `pod install`, რათა დააინტეგრიროთ დამოკიდებულებები სამუშაო სივრცის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც `xcodebuild`-ს პროექტის გენერაციის შემდეგ პირდაპირ ასრულებენ. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან თითის ანაბეჭდის ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს იმის ზუსტად განსაზღვრა, თუ რომელში ხართ:

- **გარე Swift პაკეტში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი მხარს უჭერს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით](#tuists-xcodeprojbased-integration), თქვენ აცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ით — Tuist მაკროს პროდუქტს ნატიურ მიზანში ასახავს. [Xcode-ის ნაგულისხმევი ინტეგრაციით](#xcodes-default-integration), თქვენ აცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. ბილდის ხელსაწყოების პლაგინებისგან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, საერთო ბიბლიოთეკაში თქვენს monorepo-ში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, ასე რომ შეგიძლიათ მაკროს მიზანი პირდაპირ თქვენს მანიფესტებში განაცხადოთ.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად მოდელირებს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში Swift Macro მიზნის ტიპს არ ასახელებს, Tuist მას საშუალებას აძლევს ბრძანების ხაზის ხელსაწყოს მიზნის გენერირებით, მისი მაკროს მომხმარებელი მიზნების დამოკიდებულებად ჩართვით და `-load-plugin-executable` ფლაგის მათი Swift კომპილატორის პარამეტრებში ინექციით. ეს ყველა ტექნიკური დეტალი თქვენთვის სრულდება.

ტიპური მაკრო ორ მიზნად იყოფა: **პლაგინის** მიზანი, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** მიზანი, რომელიც აცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. რადგან პლაგინი ბილდის მანქანაზე მუშაობს, მისი მიზანი მხოლოდ ჰოსტისთვისაა (macOS).

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

შემდეგ შეგიძლიათ მაკროს პლაგინისა და ბიბლიოთეკის მიზნები პირდაპირ თქვენს პროექტში განსაზღვროთ:

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

ნებისმიერ მიზანს, რომელიც უკავშირდება `MyLibrary`-ს, ახლა შეუძლია მაკროს გამოყენება — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა მისი ჩატვირთვა შეძლოს.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები და ბიბლიოთეკები შეიძლება დაკავშირდეს სტატიკურად ან დინამიურად, **არჩევანი, რომელსაც მნიშვნელოვანი გავლენა აქვს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და გაშვების დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად დიდი განხილვის გარეშე მიიღება.

**ზოგადი წესი** არის ის, რომ რელიზის ბილდებში რაც შეიძლება ბევრი რამ სტატიკურად უნდა იყოს დაკავშირებული სწრაფი გაშვების დროის მისაღწევად, ხოლო debug ბილდებში რაც შეიძლება ბევრი რამ დინამიურად უნდა იყოს დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების სირთულე იმაში მდგომარეობს, რომ Xcode-ში ეს არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ რესურსების შენახვა, სტატიკურ ჩარჩოებს ჩაშენება არ სჭირდებათ). Apple ცდილობდა პრობლემის გადაჭრას კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ახალ დინამიურ ცვლადებს ამატებს, რაც არადეტერმინიზმის ახალ წყაროებს ქმნის და შესაძლოა გამოიწვიოს ისეთი ფუნქციების, როგორიცაა Swift Previews, რომლებიც კომპილაციის გრაფს ეყრდნობიან, არასანდოობა.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურს შორის ცვლილებასთან დაკავშირებულ სირთულეს და აერთიანებს <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ებს, რომლებიც სტანდარტულია დაკავშირების ტიპების მიხედვით. <.localized_link href="/guides/features/projects/dynamic-configuration">დინამიური კონფიგურაციების გარემოს ცვლადების მეშვეობით</.localized_link> კომბინაციაში, შეგიძლიათ დაკავშირების ტიპი გამოძახების დროს გადასცეთ და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში თქვენი მიზნების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ ირჩევს მოხერხებულობას ნაგულისხმევად არაცხადი კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი ბილდის პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` ლინკერის ფლაგი](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა დარწმუნდეთ, რომ მიღებული ბინარები სწორია. შესაბამისად, ჩვენი პოზიცია არის თქვენთვის რესურსების მიწოდება, ჩვეულებრივ დოკუმენტაციის სახით, რათა სწორი გადაწყვეტილებები მიიღოთ.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift პაკეტი, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). იხილეთ მეტი დეტალი [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული სია სცენარებისა, სადაც შესაძლოა სტატიკური და დინამიური დაკავშირების შერევა დაგჭირდეთ:

- **აპლიკაციები გაფართოებებით:** რადგან აპლიკაციებს და მათ გაფართოებებს კოდის გაზიარება სჭირდებათ, შესაძლოა დაგჭირდეთ ამ მიზნების დინამიურად გახდომა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ასევე გაფართოებაში, რაც ბინარის ზომას გაზრდის.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ გეწოდებათ წინასწარ კომპილირებული ბინარები, რომლებიც არიან სტატიკური ან დინამიური. სტატიკური ბინარები შეიძლება შეიფუთოს დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დასაკავშირებლად.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება მიზნად ისახავს დაგეხმაროთ პრობლემების იდენტიფიცირებაში, რომლებიც შეიძლება წარმოიშვას მიზნის სტატიკურად დაკავშირებისგან, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ მიზანს დინამიური მიზნების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება ბინარის ზომის ზრდით ან, უარეს შემთხვევებში, შესრულების დროის კრახებით.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრაციისას, მომხმარებელ მიზანზე გარკვეული ფლაგების ჩართვა შეიძლება საჭირო იყოს შესრულების დროის კრახების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

რადგან ბილდის სისტემას და Tuist-ს არ აქვს ფლაგის საჭიროების დადგენის გზა და რადგან ფლაგს შესაძლოა არასასურველი გვერდითი ეფექტები აქვს, Tuist ამ ფლაგებს ავტომატურად არ გამოიყენებს, და რადგან Swift Package Manager `-ObjC`-ს `.unsafeFlag`-ის მეშვეობით ჩართულად მიიჩნევს, ბევრ პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როდესაც ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C მიზნებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როდესაც ეს საჭიროა `OTHER_LDFLAGS`-ის დაყენებით მომხმარებელ მიზნებზე.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად მათი სიმძლავრის — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკებს აგების პროცესში.

აქ არის რამდენიმე რჩევა, რომლის გათვალისწინებაც შეიძლება საჭირო იყოს Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დამატებულია `OTHER_LDFLAGS`-ში {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბევრი ბიბლიოთეკა დაწერილია Objective-C-ზე. ამის გამო, ნებისმიერ მომხმარებელ მიზანს სჭირდება `-ObjC` ტეგის ჩართვა თავის `OTHER_LDFLAGS` აგების პარამეტრში. ეს შეიძლება განისაზღვროს `.xcconfig` ფაილში ან ხელით მიეთითოს თქვენი Tuist მანიფესტებში მიზნის პარამეტრებში. მაგალითი:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

მეტი დეტალისთვის იხილეთ ზემოთ მოცემული [Objective-C დამოკიდებულებები](#objectivec-dependencies) განყოფილება.

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის დინამიურ ფრეიმვორკად {#set-the-product-type-for-fblpromises-to-dynamic-framework}

ზოგიერთი Google-ის ბიბლიოთეკა ეყრდნობა `FBLPromises`-ს, რომელიც ასევე Google-ის ერთ-ერთი ბიბლიოთეკაა. შეიძლება შეგხვდეთ კრახი, რომელიც `FBLPromises`-ს ახსენებს და გამოიყურება დაახლოებით ასე:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises`-ის პროდუქტის ტიპის `.framework`-ად ცალსახად დაყენება თქვენს `Package.swift` ფაილში უნდა გადაწყვიტოს პრობლემა:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავობის აღმოფხვრის განყოფილებაში](#troubleshooting), პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) `OTHER_LDFLAGS` აგების პარამეტრი უნდა დააყენოთ `$(inherited) -ObjC`-ზე. ალტერნატიულად, შეგიძლიათ გადაწეროთ პაკეტის პროდუქტის ტიპი, რათა ის იყოს დინამიური. სტატიკურად დაკავშირებისას ტესტებისა და აპლიკაციის მიზნები ჩვეულებრივ პრობლემების გარეშე მუშაობენ, მაგრამ SwiftUI პრევიუები გაფუჭებულია. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხაფანგები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დინამიურად დააკავშირებს, რითაც აპლიკაციისა და ტესტების მიზნები და SwiftUI წინასწარი ნახვები იმუშავებს.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება არ არის ყოველთვის რეკომენდებული. მეტი დეტალისთვის იხილეთ განყოფილება [სტატიკური თუ დინამიური](#static-or-dynamic). ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დაკავშირებულია დინამიურად პირობების გარეშე.


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

როდესაც დინამიური ფრეიმვორკი ან ბიბლიოთეკა ეყრდნობა სტატიკურებს `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ფრეიმვორკის ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">კომპილაციის შეცდომა გამოიწვიოს</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტზე წვდომის დონე Swift 6-ში იქნა ჩართული. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```

## დაკავშირებული {#related}

წაიკითხეთ [როგორ მიიღო monday.com-მა მოდულური პროექტის გრაფი Tuist-ით](https://tuist.dev/customers/monday), დაწყებული იმ მიზნებით, რომლებსაც ყველაზე ცოტა დამოკიდებულება აქვთ.
