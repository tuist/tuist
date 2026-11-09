---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ განაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ხშირია მისი რამდენიმე სამიზნედ დაყოფა კოდის გასაზიარებლად, საზღვრების განსასაზღვრად და აგების დროის შესამცირებლად. მრავალი სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდიფიცირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის არქიტექტურიდან გამომდინარე, დამოკიდებულების გრაფის შენარჩუნება შეიძლება იყოს შრომატევადი და შეცდომებისკენ მიდრეკილი ამოცანა. აქ არის პრობლემების მაგალითები, რომლებიც შეიძლება წააწყდეთ:

- რადგან Xcode-ის აგების სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე საქაღალდეში ათავსებს derived data-ში, სამიზნეებს შეიძლება ჰქონდეთ ისეთი პროდუქტების იმპორტის საშუალება, რაც არ უნდა ჰქონდეთ. კომპილაციები შეიძლება ჩავარდეს CI-ზე, სადაც „სუფთა“ აგებები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს `LD_RUNPATH_SEARCH_PATHS` აგების პარამეტრში მითითებულ ნებისმიერ საქაღალდეში. თუ ეს არ მოხდება, სამიზნე ვერ შეძლებს მათ პოვნას შესრულების დროს. ეს ადვილია დასაფიქრებლად და დასაყენებლად, როცა გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, მას სჭირდება დამატებითი აგების ეტაპი, რათა Xcode-მა დაამუშაოს ბანდლი და ამოიღოს სწორი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს აგების ეტაპი ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ ჩამოთვლილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრი სხვა პრობლემაც წაგვყრია. წარმოიდგინეთ, რომ გჭირდებოდათ ინჟინრების გუნდი დამოკიდებულების გრაფის შესანარჩუნებლად და მისი ვალიდურობის უზრუნველსაყოფად. ან, კიდევ უარესი, რომ ეს სირთულეები გადაწყდებოდა აგების დროს დახურული კოდის მქონე აგების სისტემით, რომელსაც ვერ აკონტროლებთ ან ვერ მორგებთ. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მა აირჩია Xcode-სა და XcodeProj-ში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ გვჯერა, რომ დამოკიდებულების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ასე შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, ხოლო დანარჩენზე ჩვენ ვზრუნავთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაქტირებულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ახდენს გრაფის ვალიდაციას პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არის ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულების გრაფის განვითარებაში მისი გაფუჭების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებულები იმავე ან სხვა პროექტების სხვა სამიზნეებზე, ასევე ბინარებზე. `Target`-ის ინსტანციირებისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი შემდეგი ვარიანტებიდან რომელიმით:

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
> დამოკიდებულების ყოველი ტიპი იღებს `condition` ოფციას, რათა პლატფორმის მიხედვით პირობითად დააკავშიროს დამოკიდებულება. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარდაუჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენი რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. მათი ინტეგრირება შეგიძლიათ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, თუმცა ყველაზე მოსახერხებელია, არ აქვს ის მოქნილობა და კონტროლი, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ ინტეგრირება მოახდინოთ Swift Packages-ის თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ თავსებადს ხდის მას ისეთ სამუშაო პროცესებთან, როგორიცაა <.localized_link href="/guides/features/cache">კეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას, სავარაუდოდ, მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციის დასამუშავებლად. თუმცა, Swift Packages-სა და XcodeProj სამიზნეებს შორის მეპინგის ლოგიკა ღია კოდისაა და საზოგადოებას შეუძლია მასში წვლილის შეტანა. ეს ეწინააღმდეგება Xcode-ის ნაგულისხმევ ინტეგრაციას, რომელიც დახურული კოდისაა და Apple-ის მიერ მხარდაჭერილი.

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
> `PackageSettings` ეგზემპლარი, რომელიც კომპილატორის დირექტივაშია გახვეული, საშუალებას გაძლევთ დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრაცია. მაგალითად, ზემოთ მოყვანილ მაგალითში ის გამოიყენება პაკეტებისთვის ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ გჭირდებათ. ასევე შეგიძლიათ გამოიყენოთ ის SwiftPM ბინარული სამიზნეებისთვის მოსალოდნელი ხელმოწერების კონფიგურირებისთვის `expectedSignatures`-ის მეშვეობით.


### ბინარული სამიზნის ხელმოწერები

თუ ლოკალური ან დისტანციური Swift პაკეტი აწვდის ბინარულ XCFramework სამიზნეს, შეგიძლიათ დააკონფიგურიროთ მისი მოსალოდნელი ხელმოწერა `PackageSettings.expectedSignatures`-ის გამოყენებით:

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
> თუ თქვენი პროექტი იყენებს მორგებულ აგების კონფიგურაციებს (კონფიგურაციები სტანდარტული `Debug`-ისა და `Release`-ის გარდა), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ინფორმაცია თქვენი პროექტის კონფიგურაციების შესახებ, რათა სწორად აიგონ. მაგალითად:
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

`Package.swift` ფაილი მხოლოდ ინტერფეისია გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომ არ განსაზღვრავთ არცერთ სამიზნეს ან პროდუქტს პაკეტში. როგორც კი დამოკიდებულებებს განსაზღვრავთ, შეგიძლიათ გაუშვათ შემდეგი ბრძანება დამოკიდებულებების გადასაწყვეტად და `Tuist/Dependencies` დირექტორიაში ჩასატვირთად:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

როგორც შეამჩნიეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გადაწყვეტა ცალკე ბრძანებით ხდება. ეს მომხმარებელს აძლევს კონტროლს იმაზე, თუ როდის სურს დამოკიდებულებების გადაწყვეტა და განახლება, და საშუალებას აძლევს გახსნას პროექტი Xcode-ში ისე, რომ ის კომპილაციისთვის მზად იყოს. ჩვენ ვფიქრობთ, რომ Apple-ის Swift Package Manager-თან ინტეგრაციით შეთავაზებული დეველოპერული გამოცდილება დროთა განმავლობაში უარესდება, როცა პროექტი იზრდება.

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

თუ გსურთ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმის გამოყენება, შეგიძლიათ გადასცეთ `packages` სია პროექტის შექმნისას:

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

როდესაც აინტეგრირებთ Swift Macro-ს ან Build Tool Plugin-ს გარე Swift Package-დან Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების გამოყენება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ საკუთარი Swift macro-ს განსაზღვრა პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM build tool plugins**
>
> SPM build tool plugins უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ იმ კონკრეტული აგების ბრძანებების აღმოჩენის მიზნით, რომლებიც სამიზნისთვის უნდა შესრულდეს. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გადაწყვეტილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ განცხადებულ გამომავალ მონაცემებზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც იმავე სამიზნის აგების ნაწილი უნდა გახდეს.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია პაკეტის პროდუქტებს ასახავს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ს არ აქვს ეკვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინს საბოლოოდ შეუძლია შესრულებადი ფაილის გაშვება, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის აგების ეტაპიდან გამოძახება არ არის პლაგინის გაშვების ეკვივალენტური: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღადგინოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, დაამოდელირებს განცხადებული შეყვანები და გამომავალი მონაცემები და დაამატოს ნებისმიერი გენერირებული ფაილი სამიზნის გრაფში, სანამ Xcode დაგეგმავს აგებას.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განცხადება და მისი `.external(name:)`-ის მეშვეობით მოხმარება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის `Project.packages`-ში განცხადება და პლაგინის პროდუქტის მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ის მეშვეობით დამატება. ეს ინარჩუნებს პლაგინს გენერირებულ Xcode პროექტთან მიბმულს, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლონ მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და აგებს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი გენერირებულ პროექტში ჩნდება როგორც Swift Package მითითება Tuist-ით გენერირებული გარე სამიზნის ნაცვლად.
- Tuist-ს არ შეუძლია პლაგინს მისცეს იგივე დონის კონტროლი, ვალიდაცია, ქეშირება და შერჩევითი ტესტირების ქცევა, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურმა აგებებმა უნდა დაუშვან Xcode-ის პაკეტის გადაწყვეტა ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. როდესაც შესაძლებელია, უპირატესობა მიანიჭეთ სამიზნეში განცხადებულ აგების ეტაპის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ Tuist-ს ან Xcode-ს გამოიძახებთ.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის „Run Build Tool Plug-ins“ აგების ეტაპის დროს. Xcode პროექტის build tool plugin-ით ერთად გენერირებისთვის, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

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

ვინაიდან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ გაუშვათ `carthage update` დამოკიდებულებების `Carthage/Build` დირექტორიაში გამოსატანად და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ეს ჩაასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **აგება და ტესტირება**
>
> თუ თქვენს პროექტს ააგებთ და ატესტებთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე დაგჭირდებათ Carthage-ით გადაწყვეტილი დამოკიდებულებების არსებობის უზრუნველყოფა `carthage update` ბრძანების გაშვებით აგებამდე ან ტესტირებამდე.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) ელის Xcode პროექტს დამოკიდებულებების ინტეგრირებისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერირებისთვის და შემდეგ გაუშვათ `pod install` დამოკიდებულებების ინტეგრირებისთვის workspace-ის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს ჩაასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერაციის შემდეგ მაშინვე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, რადგან fingerprinting ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს იმის ზუსტად მითითება, თუ რომელში ხართ:

- **გარე Swift Package-ში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი მხარს უჭერს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) შემთხვევაში, თქვენ აცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნეში. [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) შემთხვევაში, თქვენ აცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. build tool plugins-ისგან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, monorepo-ში არსებულ საერთო ბიბლიოთეკაში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, რაც საშუალებას გაძლევთ მაკროს სამიზნე პირდაპირ თქვენს მანიფესტებში განაცხადოთ.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად აღწერს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში Swift Macro სამიზნის ტიპს არ აჩენს, Tuist საშუალებას აძლევს მის გამოყენებას: ის ქმნის command-line tool სამიზნეს, აკავშირებს მას როგორც დამოკიდებულებას იმ სამიზნეებისთვის, რომლებიც იყენებენ მაკროს, და ამატებს `-load-plugin-executable` ფლაგს მათ Swift კომპილატორის პარამეტრებში. ეს ყველა ტექნიკური დეტალი Tuist-ის მიერ ავტომატურად სრულდება.

ტიპური მაკრო იყოფა ორ სამიზნედ: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც აცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. ვინაიდან პლაგინი შენების მანქანაზე მუშაობს, მისი სამიზნე მხოლოდ host-ისთვისაა (macOS).

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

ნებისმიერ სამიზნეს, რომელიც აკავშირებს `MyLibrary`-ს, ახლა შეუძლია მაკროს გამოყენება — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა შეძლოს მისი ჩატვირთვა.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები (frameworks) და ბიბლიოთეკები შეიძლება დაკავშირდეს როგორც სტატიკურად, ისე დინამიურად, **რაც მნიშვნელოვან გავლენას ახდენს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და ჩატვირთვის დრო**. მიუხედავად მისი მნიშვნელობის, ეს გადაწყვეტილება ხშირად მიიღება დიდი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ release ბილდებში რაც შეიძლება მეტი კომპონენტი უნდა იყოს სტატიკურად დაკავშირებული სწრაფი ჩატვირთვის დროის მისაღწევად, ხოლო debug ბილდებში რაც შეიძლება მეტი კომპონენტი უნდა იყოს დინამიურად დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების სირთულე იმაში მდგომარეობს, რომ Xcode-ში ეს არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ რესურსების შენახვა, სტატიკურ ჩარჩოებს არ სჭირდებათ embed-ება). Apple ცდილობდა პრობლემის გადაჭრას კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფში ახალ დინამიურ ცვლადებს ამატებს, რაც ზრდის არადეტერმინიზმის წყაროებს და შესაძლოა გამოიწვიოს ისეთი ფუნქციების, როგორიცაა Swift Previews, რომლებიც ეყრდნობიან კომპილაციის გრაფს, არასანდოობას.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურ შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ებს, რომლებიც სტანდარტულია ყველა ტიპის დაკავშირებისთვის. <.localized_link href="/guides/features/projects/dynamic-configuration">გარემოს ცვლადების მეშვეობით დინამიური კონფიგურაციების</.localized_link> კომბინაციაში, შეგიძლიათ დაკავშირების ტიპი გადასცეთ გამოძახების დროს და გამოიყენოთ ეს მნიშვნელობა თქვენს მანიფესტებში სამიზნეების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ იყენებს ნაგულისხმევად მოხერხებულობას არაცხადი კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვენდობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი build პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა უზრუნველყოთ მიღებული ბინარების სისწორე. შესაბამისად, ჩვენი მიდგომაა მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა მიიღოთ სწორი გადაწყვეტილებები.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift Package, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). იხილეთ მეტი დეტალი [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული ჩამონათვალი სცენარებისა, სადაც შესაძლოა დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** ვინაიდან აპლიკაციებს და მათ გაფართოებებს კოდის გაზიარება სჭირდებათ, შესაძლოა დაგჭირდეთ ამ სამიზნეების დინამიურად გახდა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ისე გაფართოებაში, რაც ბინარის ზომას გაზრდის.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ გეწოდებათ წინასწარ კომპილირებული ბინარები, რომლებიც არის სტატიკური ან დინამიური. სტატიკური ბინარები შეიძლება გაეხვიოს დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დაკავშირებისთვის.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება მიზნად ისახავს დაგეხმაროთ იმ პრობლემების იდენტიფიცირებაში, რომლებიც შეიძლება წარმოიშვას სამიზნის სტატიკურად დაკავშირებისას, როდესაც ის ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება ბინარის ზომის ზრდით ან, უარეს შემთხვევაში, runtime crash-ებით.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრაციისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების დამატება შეიძლება იყოს აუცილებელი runtime crash-ების თავიდან ასაცილებლად, როგორც ეს დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

ვინაიდან build სისტემას და Tuist-ს არ აქვთ ფლაგის აუცილებლობის დადგენის გზა, და ვინაიდან ფლაგს შესაძლოა არასასურველი გვერდითი ეფექტები ახლავს, Tuist არ გამოიყენებს ამ ფლაგებს ავტომატურად, და რადგან Swift Package Manager განიხილავს `-ObjC`-ს, როგორც `.unsafeFlag`-ის მეშვეობით ჩართულს, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როდესაც ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როდესაც ეს საჭიროა, მომხმარებელ სამიზნეებზე `OTHER_LDFLAGS`-ის დაყენებით.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად მათი სიმძლავრისა — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკებს აგების პროცესში.

აქ არის რამდენიმე რჩევა, რომელთა დაცვაც შეიძლება საჭირო გახდეს Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დამატებულია `OTHER_LDFLAGS`-ში {#ensure-objc-is-added-to-other_ldflags}

Google-ის ბევრი ბიბლიოთეკა დაწერილია Objective-C-ზე. ამის გამო, ნებისმიერ მომხმარებელ სამიზნეს უნდა ჰქონდეს `-ObjC` ტეგი თავის `OTHER_LDFLAGS` build პარამეტრში. ეს შეიძლება დაყენდეს `.xcconfig` ფაილში ან ხელით მიეთითოს სამიზნის პარამეტრებში თქვენს Tuist მანიფესტებში. მაგალითი:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

მეტად დეტალური ინფორმაციისთვის იხილეთ ზემოთ მოცემული [Objective-C დამოკიდებულებები](#objectivec-dependencies) სექცია.

#### დააყენეთ პროდუქტის ტიპი `FBLPromises`-ისთვის, როგორც დინამიური ფრეიმვორკი {#set-the-product-type-for-fblpromises-to-dynamic-framework}

ზოგიერთი Google ბიბლიოთეკა ეყრდნობა `FBLPromises`-ს, რომელიც ასევე Google-ის ერთ-ერთი ბიბლიოთეკაა. შეიძლება წააწყდეთ კრახს, რომელიც `FBLPromises`-ს ახსენებს და ასე გამოიყურება:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავი სიტუაციების გადაჭრის](#troubleshooting) სექციაში, პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) უნდა დააყენოთ `OTHER_LDFLAGS` build პარამეტრი `$(inherited) -ObjC`-ზე. ალტერნატიულად, შეგიძლიათ გადააწეროთ პაკეტის პროდუქტის ტიპი, რათა ის იყოს დინამიური. სტატიკურად დაკავშირებისას, ტესტისა და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI previews გაფუჭებულია. ეს შეიძლება გადაწყდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია, როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხარვეზები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დინამიურად დააკავშირებს — შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI previews იმუშავებს.

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

როდესაც დინამიური ფრეიმვორკი ან ბიბლიოთეკა ეყრდნობა სტატიკურებს `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ფრეიმვორკის ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">კომპილაციის შეცდომა გამოიწვიოს</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტზე წვდომის დონე Swift 6-ში ჩაირთო. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```
