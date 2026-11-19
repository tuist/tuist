---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ განაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ჩვეულებრივია მისი რამდენიმე სამიზნედ დაყოფა კოდის გასაზიარებლად, საზღვრების განსასაზღვრად და ბილდის დროის გასაუმჯობესებლად. მრავალი სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულებების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის დიზაინის გამო, დამოკიდებულებების გრაფის შენარჩუნება შეიძლება იყოს შრომატევადი და შეცდომების მიმართ მგრძნობიარე ამოცანა. აქ არის რამდენიმე მაგალითი პრობლემებისა, რომლებიც შეიძლება წააწყდეთ:

- ვინაიდან Xcode-ის ბილდის სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე დირექტორიაში ათავსებს derived data-ში, სამიზნეებს შეიძლება ჰქონდეთ შესაძლებლობა, შემოიტანონ ისეთი პროდუქტები, რომლებიც არ უნდა შემოჰქონდეთ. კომპილაციები შეიძლება ჩავარდეს CI-ზე, სადაც სუფთა ბილდები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა გადაიტანოთ იმ დირექტორიებში, რომლებიც შედიან `LD_RUNPATH_SEARCH_PATHS` ბილდის პარამეტრში. თუ ეს არ გაკეთდა, სამიზნე ვერ იპოვის მათ გაშვების დროს. ეს ადვილია გასააზრებლად და დასაყენებლად, როდესაც გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, სამიზნეს სჭირდება დამატებითი ბილდის ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს სწორი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს ბილდის ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ მოყვანილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრად მეტი შეგვხვდა. წარმოიდგინეთ, თუ გჭირდებოდათ ინჟინრების გუნდი დამოკიდებულებების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად. ან კიდევ უარესი, რომ სირთულეები გადაწყვეტილიყო ბილდის დროს დახურული კოდის მქონე ბილდის სისტემით, რომელსაც ვერ აკონტროლებთ ან ვერ ადაპტირებთ. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მა აირჩია Xcode-სა და XcodeProj-ში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ გვჯერა, რომ დამოკიდებულებების გრაფი უნდა იყოს **აშკარა** და **სტატიკური**, რადგან მხოლოდ ასე შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, ხოლო დანარჩენზე ჩვენ ვზრუნავთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაქტულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ამოწმებს გრაფს პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულებების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებული სხვა სამიზნეებზე იმავე და სხვა პროექტებში, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი შემდეგი ვარიანტებიდან რომელიმეთი:

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
> დამოკიდებულების ყოველი ტიპი იღებს `condition` ოფციას, რათა პირობითად დააკავშიროს დამოკიდებულება პლატფორმის მიხედვით. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარდაჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას, განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. Tuist იყენებს Swift Package Manager-ს მათ გადასაწყვეტად; იმის შესახებ, თუ როგორ შეედრება ლოკალური პაკეტებით მოდულარიზაცია Tuist პროექტს, იხილეთ [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager). მათი ინტეგრაცია შეგიძლიათ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, აკლია ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის დასაძლევად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ, ინტეგრირება გაუკეთოთ Swift Packages-ს თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ თავსებადს ხდის მას ისეთ სამუშაო ნაკადებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას სავარაუდოდ მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციების დასამუშავებლად. თუმცა, Swift Packages-სა და XcodeProj სამიზნეებს შორის ასახვის ლოგიკა ღია კოდია და საზოგადოებას შეუძლია შეიტანოს წვლილი. ეს საპირისპიროა Xcode-ის ნაგულისხმევი ინტეგრაციისა, რომელიც დახურული კოდია და Apple-ის მიერ შენარჩუნდება.

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
> `PackageSettings` ინსტანსი, რომელიც გახვეულია კომპილატორის დირექტივაში, საშუალებას გაძლევთ, დააკონფიგურიროთ, თუ როგორ ინტეგრირდება პაკეტები. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის გამოყენებული ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ უნდა დაგჭირდეთ. ასევე შეგიძლიათ გამოიყენოთ იმისთვის, რომ დააკონფიგურიროთ მოსალოდნელი ხელმოწერები SwiftPM ბინარული სამიზნეებისთვის `expectedSignatures`-ის მეშვეობით.


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
> თუ თქვენი პროექტი იყენებს მორგებულ ბილდის კონფიგურაციებს (კონფიგურაციები, განსხვავებული სტანდარტული `Debug` და `Release`-გან), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ინფორმაცია თქვენი პროექტის კონფიგურაციების შესახებ, რათა სწორად ააწყონ. მაგალითად:
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

`Package.swift` ფაილი მხოლოდ ინტერფეისია გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომ არ განსაზღვრავთ არცერთ სამიზნეს ან პროდუქტს პაკეტში. მას შემდეგ, რაც დამოკიდებულებებს განსაზღვრავთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების გადასაწყვეტად და `Tuist/Dependencies` დირექტორიაში ჩამოსატანად:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გადაწყვეტა ცალკე ბრძანებაა. ეს მომხმარებლებს აძლევს კონტროლს იმაზე, თუ როდის სურთ დამოკიდებულებების გადაწყვეტა და განახლება, და საშუალებას აძლევს გახსნან პროექტი Xcode-ში ისე, რომ ის მზად იყოს კომპილაციისთვის. ჩვენ გვჯერა, რომ Apple-ის Swift Package Manager-თან ინტეგრაციით უზრუნველყოფილი დეველოპერული გამოცდილება დროთა განმავლობაში, პროექტის ზრდასთან ერთად, უარესდება.

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
> **სქემები** ავტომატურად არ იქმნება Swift Package პროექტებისთვის, რათა სქემების სია სუფთა დარჩეს. შეგიძლიათ შექმნათ ისინი Xcode-ის UI-ის მეშვეობით.


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

გარე Swift პაკეტიდან Swift Macro-ს ან Build Tool Plugin-ის ინტეგრირებისას Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების მოხმარება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ საკუთარი Swift macro-ს განსაზღვრა პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM build tool plugins**
>
> SPM build tool plugins უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ იმ კონკრეტული ბილდის ბრძანებების აღმოჩენის მიზნით, რომლებიც სამიზნისთვის უნდა შესრულდეს. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გადაწყვეტილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ განაცხადებულ გამომავალ მონაცემებზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც იმავე სამიზნის ბილდის ნაწილი უნდა გახდეს.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია პაკეტის პროდუქტებს ასახავს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად, ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ს არ გააჩნია ეკვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინს საბოლოოდ შეუძლია შესრულებადი ფაილის გაშვება, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის ბილდის ფაზიდან გამოძახება არ არის პლაგინის გაშვების ეკვივალენტური: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღწარმოოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, დაამოდელიროს განაცხადებული შეყვანები და გამომავალი მონაცემები და დაამატოს ნებისმიერი გენერირებული ფაილი სამიზნის გრაფში, სანამ Xcode დაგეგმავს ბილდს.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განაცხადება და `.external(name:)`-ის მეშვეობით მისი მოხმარება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის განაცხადება `Project.packages`-ში და პლაგინის პროდუქტის დამატება მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ის გამოყენებით. ეს ინარჩუნებს პლაგინს მიბმულს გენერირებულ Xcode პროექტთან, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლონ მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და აწყობს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი გენერირებულ პროექტში ჩანს როგორც Swift Package მითითება Tuist-ით გენერირებული გარე სამიზნის ნაცვლად.
- Tuist ვერ აძლევს პლაგინს იმავე დონის კონტროლს, ვალიდაციას, ქეშირებას და შერჩევითი ტესტირების ქცევას, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურმა ბილდებმა უნდა დაუშვან Xcode-ის პაკეტის გადაწყვეტა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვურჩევთ SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. შესაძლებლობის შემთხვევაში, უპირატესობა მიანიჭეთ სამიზნეში განაცხადებულ ბილდის ფაზის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ Tuist-ს ან Xcode-ს გამოიძახებთ.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ ბილდის ფაზის დროს. Xcode პროექტის გენერირებისთვის build tool plugin-ის შენარჩუნებით, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

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

ვინაიდან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update` დამოკიდებულებების `Carthage/Build` დირექტორიაში გამოსატანად და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერირებამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ბილდი და ტესტი**
>
> თუ თქვენს პროექტს აწყობთ და ტესტავთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე უნდა დარწმუნდეთ, რომ Carthage-ით გადაწყვეტილი დამოკიდებულებები არსებობს `carthage update` ბრძანების გაშვებით ბილდის ან ტესტირების წინ.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) მოითხოვს Xcode პროექტს დამოკიდებულებების ინტეგრირებისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერირებისთვის და შემდეგ გაუშვათ `pod install` დამოკიდებულებების ინტეგრირებისთვის, სამუშაო სივრცის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერირებამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერირებისთანავე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან თითის ანაბეჭდის ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს ცალსახად მიუთითოთ, თუ რომელში ხართ:

- **გარე Swift პაკეტში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი მხარს უჭერს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით](#tuists-xcodeprojbased-integration), თქვენ განაცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნეში. [Xcode-ის ნაგულისხმევი ინტეგრაციით](#xcodes-default-integration), თქვენ განაცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. Build tool plugins-ისგან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, საერთო ბიბლიოთეკაში თქვენს monorepo-ში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, ასე რომ შეგიძლიათ მაკროს სამიზნე პირდაპირ განაცხადოთ თქვენს მანიფესტებში.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად მოდელირებს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში არ ასახავს Swift Macro სამიზნის ტიპს, Tuist საშუალებას გაძლევთ ამის გაკეთებას command-line tool სამიზნის გენერირებით, მისი მაკროს მომხმარებელი სამიზნეების დამოკიდებულებად მიბმით და `-load-plugin-executable` ფლაგის ინექციით მათ Swift კომპილატორის პარამეტრებში. ეს ყველაფერი თქვენთვის ავტომატურად სრულდება.

ტიპური მაკრო იყოფა ორ სამიზნედ: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც განაცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განაცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. რადგან პლაგინი მუშაობს აგების მანქანაზე, მისი სამიზნე მხოლოდ ჰოსტისთვისაა (macOS).

მაკროს იმპლემენტაცია ეყრდნობა [swift-syntax](https://github.com/swiftlang/swift-syntax)-ს, რომელსაც თქვენ განაცხადებთ როგორც ჩვეულებრივ გარე დამოკიდებულებას `Tuist/Package.swift`-ში:

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

შემდეგ შეგიძლიათ მაკროს პლაგინისა და ბიბლიოთეკის სამიზნეები პირდაპირ განსაზღვროთ თქვენს პროექტში:

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

ნებისმიერ სამიზნეს, რომელიც აკავშირებს `MyLibrary`-ს, ახლა შეუძლია გამოიყენოს მაკრო — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა შეძლოს მისი ჩატვირთვა.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები და ბიბლიოთეკები შეიძლება დაკავშირდეს როგორც სტატიკურად, ისე დინამიურად, **არჩევანი, რომელსაც მნიშვნელოვანი გავლენა აქვს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და ჩატვირთვის დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად მიიღება დიდი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ რელიზის აგებებში რაც შეიძლება მეტი რამ გსურთ იყოს სტატიკურად დაკავშირებული სწრაფი ჩატვირთვის დროის მისაღწევად, ხოლო debug აგებებში რაც შეიძლება მეტი რამ გსურთ იყოს დინამიურად დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების სირთულე იმაში მდგომარეობს, რომ Xcode-ში ეს არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ შეიცავდნენ რესურსებს, სტატიკურ ჩარჩოებს არ სჭირდებათ ჩაშენება). Apple-მა სცადა პრობლემის გადაჭრა კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ამატებს ახალ დინამიურ ცვლადებს, რაც ზრდის არადეტერმინიზმის წყაროებს და პოტენციურად იწვევს ისეთი ფუნქციების, როგორიცაა Swift Previews, რომლებიც ეყრდნობიან კომპილაციის გრაფს, არასანდოობას.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურ შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ს, რომლებიც სტანდარტულია დაკავშირების ტიპების მიხედვით. <.localized_link href="/guides/features/projects/dynamic-configuration">დინამიური კონფიგურაციების გარემოს ცვლადების მეშვეობით</.localized_link> კომბინაციაში, შეგიძლიათ გადასცეთ დაკავშირების ტიპი გამოძახების დროს და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში თქვენი სამიზნეების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ იყენებს ნაგულისხმევად მოხერხებულობას არაცხადი კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი აგების პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` ლინკერის ფლაგი](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა უზრუნველყოთ მიღებული ბინარების სისწორე. შესაბამისად, ჩვენი პოზიციაა მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა მიიღოთ სწორი გადაწყვეტილებები.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift პაკეტი, რომელსაც ბევრი პროექტი აინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). იხილეთ მეტი დეტალი [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული ჩამონათვალი სცენარებისა, სადაც შეიძლება დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** რადგან აპლიკაციებს და მათ გაფართოებებს სჭირდებათ კოდის გაზიარება, შეიძლება დაგჭირდეთ ამ სამიზნეების დინამიურად გახდა. წინააღმდეგ შემთხვევაში, მიიღებთ იგივე კოდის დუბლირებას როგორც აპლიკაციაში, ისე გაფართოებაში, რაც ზრდის ბინარის ზომას.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ გეძლევათ წინასწარ კომპილირებული ბინარები, რომლებიც არიან ან სტატიკური, ან დინამიური. სტატიკური ბინარები შეიძლება შეიფუთოს დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დასაკავშირებლად.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება განკუთვნილია დაგეხმაროთ ამოიცნოთ პრობლემები, რომლებიც შეიძლება წარმოიშვას სამიზნის სტატიკურად დაკავშირებისგან, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება როგორც გაზრდილი ბინარის ზომა ან, უარეს შემთხვევაში, შესრულების დროს კრახები.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრირებისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების ჩართვა შეიძლება იყოს საჭირო შესრულების დროს კრახების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

რადგან აგების სისტემას და Tuist-ს არ აქვს გზა იმის დასადგენად, არის თუ არა ფლაგი საჭირო, და რადგან ფლაგს თან ახლავს პოტენციურად არასასურველი გვერდითი ეფექტები, Tuist არ გამოიყენებს ამ ფლაგებს ავტომატურად, და რადგან Swift Package Manager განიხილავს `-ObjC`-ს, როგორც ჩართულს `.unsafeFlag`-ის მეშვეობით, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როდესაც ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როდესაც საჭიროა `OTHER_LDFLAGS`-ის დაყენებით მომხმარებელ სამიზნეებზე.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად იმისა, რომ ძლიერია — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკას აგების პროცესში.

აქ არის რამდენიმე რჩევა, რომელთა დაცვაც შეიძლება საჭირო იყოს Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დამატებულია `OTHER_LDFLAGS`-ში {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბიბლიოთეკების უმეტესობა დაწერილია Objective-C-ზე. ამის გამო, ნებისმიერ მომხმარებელ სამიზნეს დასჭირდება `-ObjC` ტეგის ჩართვა თავის `OTHER_LDFLAGS` აგების პარამეტრში. ეს შეიძლება დაყენდეს `.xcconfig` ფაილში ან ხელით მიეთითოს სამიზნის პარამეტრებში თქვენს Tuist მანიფესტებში. მაგალითი:

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

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის როგორც დინამიური ჩარჩო {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Google-ის გარკვეული ბიბლიოთეკები დამოკიდებულია `FBLPromises`-ზე, Google-ის კიდევ ერთ ბიბლიოთეკაზე. შეიძლება შეგხვდეთ კრეში, რომელიც მოიხსენიებს `FBLPromises`-ს და გამოიყურება დაახლოებით ასე:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises`-ის პროდუქტის ტიპის ცალსახად `.framework`-ად დაყენება თქვენს `Package.swift` ფაილში უნდა გადაწყვიტოს პრობლემა:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავი სიტუაციების გადაჭრის](#troubleshooting) განყოფილებაში, პაკეტების სტატიკურად დაკავშირებისას დაგჭირდებათ `OTHER_LDFLAGS` აგების პარამეტრის დაყენება `$(inherited) -ObjC`-ზე, რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია. ალტერნატიულად, შეგიძლიათ გადააწეროთ პაკეტის პროდუქტის ტიპი, რომ იყოს დინამიური. სტატიკურად დაკავშირებისას, ტესტის და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI წინასწარი ნახვები არ მუშაობს. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხაფანგები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დააკავშირებს დინამიურად - შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI წინასწარი ნახვები იმუშავებს.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება ყოველთვის არ არის რეკომენდებული. იხილეთ განყოფილება [სტატიკური თუ დინამიური](#static-or-dynamic) მეტი დეტალისთვის. ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დაკავშირებულია დინამიურად პირობების გარეშე.


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
> `import Sharing`-ის ნაცვლად, უნდა გამოიყენოთ `import SwiftSharing`.


### ტრანზიტული სტატიკური დამოკიდებულებების გაჟონვა `.swiftmodule`-ის მეშვეობით {#transitive-static-dependencies-leaking-through-swiftmodule}

როდესაც დინამიური ჩარჩო ან ბიბლიოთეკა დამოკიდებულია სტატიკურებზე `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ჩარჩოს ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც პოტენციურად შეიძლება <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">გამოიწვიოს კომპილაციის შეცდომა</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტზე წვდომის დონე ჩართულია Swift 6-ში. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```

## დაკავშირებული {#related}

წაიკითხეთ [როგორ მიიღო monday.com-მა მოდულური პროექტის გრაფი Tuist-ით](https://tuist.dev/customers/monday), დაწყებული იმ სამიზნეებით, რომლებსაც ყველაზე ნაკლები დამოკიდებულება აქვთ.
