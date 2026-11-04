---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოაცხადოთ დამოკიდებულებები თქვენს Tuist პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ჩვეულებრივია მისი რამდენიმე სამიზნედ დაყოფა კოდის გასაზიარებლად, საზღვრების განსასაზღვრად და აგების დროის შესამცირებლად. რამდენიმე სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულებების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის დიზაინის გამო, დამოკიდებულებების გრაფის შენარჩუნება შეიძლება იყოს მოწყენითი და შეცდომებისკენ მიდრეკილი ამოცანა. აქ არის რამდენიმე მაგალითი პრობლემებისა, რომლებიც შეიძლება შეგხვდეთ:

- რადგან Xcode-ის აგების სისტემა პროექტის ყველა პროდუქტს წარმოქმნილ მონაცემებში ერთსა და იმავე საქაღალდეში ასახავს, სამიზნეებს შეიძლება ჰქონდეთ პროდუქტების იმპორტის შესაძლებლობა, რაც არ უნდა ჰქონდეთ. კომპილაციები შეიძლება ჩავარდეს CI-ზე, სადაც სუფთა აგებები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს ნებისმიერ საქაღალდეში, რომელიც შედის `LD_RUNPATH_SEARCH_PATHS` აგების პარამეტრში. თუ ეს არ გაკეთდა, სამიზნე ვერ იპოვის მათ გაშვების დროს. ეს ადვილია გასააზრებლად და დასაყენებლად, როდესაც გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, სამიზნეს სჭირდება დამატებითი აგების ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს სწორი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს აგების ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ მოყვანილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრად მეტს შევეჩეხეთ. წარმოიდგინეთ, თუ დამოკიდებულებების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად ინჟინრების გუნდი დაგჭირდებოდათ. ან კიდევ უარესი, რომ სირთულეები გადაწყვეტილიყო აგების დროს დახურული კოდის მქონე აგების სისტემით, რომლის კონტროლი ან მორგებაც არ შეგიძლიათ. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მ აირჩია Xcode-სა და XcodeProj-ში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ გვჯერა, რომ დამოკიდებულებების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ამ შემთხვევაში შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, ხოლო დანარჩენზე ჩვენ ვზრუნავთ. სირთულეები და განხორციელების დეტალები თქვენგან აბსტრაქირებულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ამოწმებს გრაფს პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულებების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებულნი იმავე და სხვა პროექტების სხვა სამიზნეებზე, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი შემდეგი ვარიანტებიდან რომელიმით:

- `Target`: აცხადებს დამოკიდებულებას იმავე პროექტის სამიზნესთან.
- `Project`: აცხადებს დამოკიდებულებას სხვა პროექტის სამიზნესთან.
- `Framework`: აცხადებს დამოკიდებულებას ბინარულ ფრეიმვორკთან.
- `Library`: აცხადებს დამოკიდებულებას ბინარულ ბიბლიოთეკასთან.
- `XCFramework`: აცხადებს დამოკიდებულებას ბინარულ XCFramework-თან.
- `SDK`: აცხადებს დამოკიდებულებას სისტემურ SDK-თან.
- `XCTest`: აცხადებს დამოკიდებულებას XCTest-თან.
- `Macro`: აცხადებს დამოკიდებულებას იმავე პროექტში განსაზღვრულ Swift macro სამიზნესთან (იხილეთ [Swift Macros](#swift-macros)).

> [!NOTE]
> **დამოკიდებულების პირობები**
>
> ყველა ტიპის დამოკიდებულება იღებს `condition` პარამეტრს, რათა პლატფორმის მიხედვით პირობითად დააკავშიროს დამოკიდებულება. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარს უჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. შეგიძლიათ მათი ინტეგრირება Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, არ აქვს ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახავად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ ინტეგრირება მოახდინოთ Swift Packages-ის თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ ვხდით მას თავსებად ისეთ სამუშაო ნაკადებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას, სავარაუდოდ, მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციის დასამუშავებლად. თუმცა, მაპინგის ლოგიკა Swift Packages-სა და XcodeProj სამიზნეებს შორის არის ღია კოდის მქონე და საზოგადოებას შეუძლია მასში წვლილის შეტანა. ეს ეწინააღმდეგება Xcode-ის ნაგულისხმევ ინტეგრაციას, რომელიც დახურული კოდის მქონეა და Apple-ის მიერ არის შენარჩუნებული.

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
> `PackageSettings` ინსტანსი, რომელიც გახვეულია კომპილატორის დირექტივაში, საშუალებას გაძლევთ დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრირება. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის გამოყენებული ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ უნდა დაგჭირდეთ. ასევე შეგიძლიათ გამოიყენოთ ის SwiftPM ბინარული სამიზნეებისთვის მოსალოდნელი ხელმოწერების დასაკონფიგურირებლად `expectedSignatures`-ის მეშვეობით.


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
> თუ თქვენი პროექტი იყენებს მორგებულ აგების კონფიგურაციებს (კონფიგურაციები, რომლებიც განსხვავდება სტანდარტული `Debug` და `Release`-გან), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ინფორმაცია თქვენი პროექტის კონფიგურაციების შესახებ, რათა სწორად აიგონ. მაგალითად:
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

`Package.swift` ფაილი არის მხოლოდ ინტერფეისი გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომ არ განსაზღვრავთ არცერთ სამიზნეს ან პროდუქტს პაკეტში. ერთხელ როცა დამოკიდებულებები განსაზღვრული გაქვთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების გადასაწყვეტად და `Tuist/Dependencies` საქაღალდეში ჩასატვირთად:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გადაწყვეტა ცალკე ბრძანებაა. ეს მომხმარებლებს აძლევს კონტროლს იმაზე, თუ როდის სურთ დამოკიდებულებების გადაწყვეტა და განახლება, და საშუალებას აძლევს გახსნან Xcode პროექტი ისე, რომ ის მზად იყოს კომპილაციისთვის. ეს არის ის სფერო, სადაც, ჩვენი აზრით, Apple-ის Swift Package Manager-თან ინტეგრაციით შეთავაზებული დეველოპერული გამოცდილება დროთა განმავლობაში უარესდება, რადგან პროექტი იზრდება.

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
> **სქემები** ავტომატურად არ იქმნება Swift Package პროექტებისთვის, რათა სქემების სია სუფთა დარჩეს. შეგიძლიათ შექმნათ ისინი Xcode-ის UI-ის მეშვეობით.


#### Xcode-ის ნაგულისხმევი ინტეგრაცია {#xcodes-default-integration}

თუ გსურთ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმის გამოყენება, შეგიძლიათ გადასცეთ სია `packages` პროექტის შექმნისას:

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

როდესაც აერთიანებთ Swift Macro-ს ან Build Tool Plugin-ს გარე Swift Package-დან Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების გამოყენება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ საკუთარი Swift macro-ს განსაზღვრა პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM Build Tool Plugins**
>
> SPM build tool plugins უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ, რათა აღმოაჩინონ კონკრეტული აგების ბრძანებები, რომლებიც უნდა შესრულდეს სამიზნისთვის. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გადაწყვეტილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ განცხადებულ გამომავალ მონაცემებზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც უნდა გახდნენ იმავე სამიზნის აგების ნაწილი.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია ასახავს პაკეტის პროდუქტებს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად, ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ს არ აქვთ ექვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინს საბოლოოდ შეუძლია შესრულებადი ფაილის გაშვება, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის აგების ეტაპიდან გამოძახება არ არის იგივე, რაც პლაგინის გაშვება: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღადგინოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, მოახდინოს განცხადებული შეყვანების და გამომავალი მონაცემების მოდელირება და დაამატოს ნებისმიერი შექმნილი ფაილი სამიზნის გრაფში, სანამ Xcode დაგეგმავს აგებას.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განცხადება და მისი `.external(name:)`-ის მეშვეობით მოხმარება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის განცხადება `Project.packages`-ში და პლაგინის პროდუქტის დამატება მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ით. ეს ინარჩუნებს პლაგინს მიბმულს შექმნილ Xcode პროექტთან, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლოს მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და აგებს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი ჩნდება შექმნილ პროექტში, როგორც Swift Package მითითება Tuist-ით შექმნილი გარე სამიზნის ნაცვლად.
- Tuist-ს არ შეუძლია მისცეს პლაგინს იგივე დონის კონტროლი, ვალიდაცია, ქეშირება და შერჩევითი ტესტირების ქცევა, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურმა აგებებმა უნდა დაუშვან Xcode-ის პაკეტის გადაწყვეტა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. როცა შესაძლებელია, უპირატესობა მიანიჭეთ სამიზნეში განცხადებულ აგების ეტაპის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან შექმნილი Xcode პროექტის გარეთ, სანამ გამოიძახებთ Tuist-ს ან Xcode-ს.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ აგების ეტაპის დროს. Xcode პროექტის შესაქმნელად build tool plugin-ის შენარჩუნებით, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

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

რადგან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update`, რათა გამოიტანოთ დამოკიდებულებები `Carthage/Build` დირექტორიაში და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ჩაასვათ ეს სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერირებამდე.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **აგება და ტესტირება**
>
> თუ თქვენს პროექტს ააგებთ და ტესტავთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე უნდა დარწმუნდეთ, რომ Carthage-ით გადაწყვეტილი დამოკიდებულებები არსებობს `carthage update` ბრძანების გაშვებით აგებამდე ან ტესტირებამდე.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) მოითხოვს Xcode პროექტს დამოკიდებულებების ინტეგრაციისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის შესაქმნელად და შემდეგ გაუშვათ `pod install`, რათა ინტეგრირდეს დამოკიდებულებები სამუშაო სივრცის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ჩაასვათ ეს სკრიპტში, რომლის გაშვებაც შეგიძლიათ პროექტის გენერირებამდე.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერირების შემდეგ მაშინვე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან თითის ანაბეჭდის ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს იმის ზუსტად მითითება, თუ რომელში ხართ:

- **გარე Swift Package-ში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი მხარს უჭერს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით](#tuists-xcodeprojbased-integration), თქვენ აცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნედ. [Xcode-ის ნაგულისხმევი ინტეგრაციით](#xcodes-default-integration), თქვენ აცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. build tool plugins-გან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, საერთო ბიბლიოთეკაში თქვენს monorepo-ში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, ასე რომ შეგიძლიათ მაკროს სამიზნე პირდაპირ თქვენს მანიფესტებში განაცხადოთ.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად აღწერს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში Swift Macro სამიზნის ტიპს არ წარმოადგენს, Tuist მას საშუალებას აძლევს command-line tool სამიზნის გენერირებით, მისი მაკროს მომხმარებელი სამიზნეების დამოკიდებულებად დაყენებით და `-load-plugin-executable` ფლაგის მათ Swift კომპილატორის პარამეტრებში ჩასმით. ეს ყველაფერი თქვენთვის ავტომატურად სრულდება.

ტიპური მაკრო ორ სამიზნედ იყოფა: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც აცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. რადგან პლაგინი build machine-ზე მუშაობს, მისი სამიზნე მხოლოდ host-ისთვისაა (macOS).

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

ჩარჩოები და ბიბლიოთეკები შეიძლება დაკავშირდეს როგორც სტატიკურად, ისე დინამიურად, **რაც მნიშვნელოვნად მოქმედებს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და ჩატვირთვის დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად მიიღება დიდი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ release აწყობებში რაც შეიძლება მეტი რამ უნდა იყოს სტატიკურად დაკავშირებული სწრაფი ჩატვირთვის დროის მისაღწევად, ხოლო debug აწყობებში რაც შეიძლება მეტი რამ უნდა იყოს დინამიურად დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების გამოწვევა Xcode-ში არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ რესურსების შენახვა, სტატიკურ ჩარჩოებს ჩაშენება არ სჭირდებათ). Apple ცდილობდა პრობლემის გადაჭრას კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ამატებს ახალ დინამიურ ცვლადებს, რაც ზრდის არადეტერმინიზმის წყაროებს და შესაძლოა გახადოს არასაიმედო ისეთი ფუნქციები, როგორიცაა Swift Previews, რომლებიც კომპილაციის გრაფს ეყრდნობა.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურ შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ს, რომლებიც სტანდარტულია ყველა ტიპის დაკავშირებისთვის. <.localized_link href="/guides/features/projects/dynamic-configuration">dynamic configurations via environment variables</.localized_link>-თან კომბინაციაში, შეგიძლიათ დაკავშირების ტიპი გამოძახების დროს გადასცეთ და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში სამიზნეების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ ირჩევს მოხერხებულობას არაცხადი კონფიგურაციით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი აწყობის პარამეტრის დაყენებას, რომელიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა დარწმუნდეთ, რომ მიღებული ბინარები სწორია. შესაბამისად, ჩვენი მიდგომაა მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა სწორი გადაწყვეტილებები მიიღოთ.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift Package, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). მეტი დეტალი იხილეთ [ამ განყოფილებაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული ჩამონათვალი სცენარებისა, სადაც შესაძლოა დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** რადგან აპლიკაციებს და მათ გაფართოებებს კოდის გაზიარება სჭირდებათ, შესაძლოა დაგჭირდეთ იმ სამიზნეების დინამიურად გახდა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ისე გაფართოებაში, რაც ბინარის ზომას გაზრდის.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ გეძლევათ წინასწარ კომპილირებული ბინარები, რომლებიც არის სტატიკური ან დინამიური. სტატიკური ბინარები შეიძლება ჩაისვას დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დასაკავშირებლად.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება გეხმარებათ იმ პრობლემების იდენტიფიცირებაში, რომლებიც შეიძლება წარმოიშვას სამიზნის სტატიკურად დაკავშირებისას, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება ბინარის ზომის ზრდით ან, უარეს შემთხვევაში, runtime crash-ებით.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრირებისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების ჩართვა შეიძლება საჭირო იყოს runtime crash-ების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

რადგან აწყობის სისტემას და Tuist-ს არ აქვს ფლაგის საჭიროების დადგენის გზა და რადგან ფლაგს შესაძლოა არასასურველი გვერდითი ეფექტები აქვს, Tuist ამ ფლაგებს ავტომატურად არ აყენებს, და რადგან Swift Package Manager `-ObjC`-ს განიხილავს როგორც `.unsafeFlag`-ის მეშვეობით ჩასმულს, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როცა ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როცა საჭიროა, `OTHER_LDFLAGS`-ის დაყენებით მომხმარებელ სამიზნეებზე.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად მათი სიმძლავრის — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკას აწყობისას.

აქ არის რამდენიმე რჩევა, რომლის დაცვაც შეიძლება საჭირო იყოს Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დაემატა `OTHER_LDFLAGS`-ს {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბიბლიოთეკების უმეტესობა Objective-C-ზეა დაწერილი. ამის გამო, ნებისმიერ მომხმარებელ სამიზნეს უნდა ჰქონდეს `-ObjC` ტეგი ჩართული თავის `OTHER_LDFLAGS` აწყობის პარამეტრში. ეს შეიძლება დაყენდეს `.xcconfig` ფაილში ან ხელით მიეთითოს სამიზნის პარამეტრებში თქვენს Tuist მანიფესტებში. მაგალითი:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

მეტი დეტალისთვის იხილეთ ზემოთ მოცემული სექცია [Objective-C დამოკიდებულებები](#objective-c-dependencies).

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის როგორც დინამიური ფრეიმვორკი {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Google-ის გარკვეული ბიბლიოთეკები ეყრდნობიან `FBLPromises`-ს, Google-ის კიდევ ერთ ბიბლიოთეკას. შეიძლება წააწყდეთ crash-ს, რომელიც `FBLPromises`-ს ახსენებს და ასე გამოიყურება:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises`-ის პროდუქტის ტიპის ცალსახად `.framework`-ად დაყენება თქვენს `Package.swift` ფაილში უნდა გადაჭრას პრობლემა:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავი პრობლემების გადაჭრის](#troubleshooting) სექციაში, პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) უნდა დააყენოთ `OTHER_LDFLAGS` აწყობის პარამეტრი მნიშვნელობაზე `$(inherited) -ObjC`. ალტერნატიულად, შეგიძლიათ გადაწეროთ პაკეტის პროდუქტის ტიპი დინამიურად. სტატიკურად დაკავშირებისას, ტესტის და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI previews გაფუჭებულია. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხაფანგები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დინამიურად დააკავშირებს — შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI previews იმუშავებენ.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება არ არის ყოველთვის რეკომენდებული. იხილეთ სექცია [სტატიკური თუ დინამიური](#static-or-dynamic) მეტი დეტალისთვის. ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დინამიურად არის დაკავშირებული პირობების გარეშე.


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

როდესაც დინამიური ფრეიმვორკი ან ბიბლიოთეკა დამოკიდებულია სტატიკურებზე `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ფრეიმვორკის ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">კომპილაციის შეცდომა გამოიწვიოს</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტებზე წვდომის დონე Swift 6-ში ჩაირთო. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```
