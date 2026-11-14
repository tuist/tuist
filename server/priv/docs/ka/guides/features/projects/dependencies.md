---
{
  "title": "დამოკიდებულებები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ განაცხადოთ დამოკიდებულებები თქვენს Tuist-ის პროექტში."
}
---
# დამოკიდებულებები {#dependencies}

როდესაც პროექტი იზრდება, ხშირად მას რამდენიმე სამიზნედ ყოფენ კოდის გასაზიარებლად, საზღვრების განსაზღვრისა და ბილდის დროის შესამცირებლად. მრავალი სამიზნე ნიშნავს მათ შორის დამოკიდებულებების განსაზღვრას, რაც ქმნის **დამოკიდებულების გრაფს**, რომელიც შეიძლება მოიცავდეს გარე დამოკიდებულებებსაც.

## XcodeProj-ით კოდირებული გრაფები {#xcodeprojcodified-graphs}

Xcode-ისა და XcodeProj-ის არქიტექტურის გამო, დამოკიდებულების გრაფის შენარჩუნება შეიძლება იყოს შრომატევადი და შეცდომების მიმართ მგრძნობიარე ამოცანა. აქ მოცემულია ზოგიერთი პრობლემა, რომელთა წინაშეც შეიძლება აღმოჩნდეთ:

- ვინაიდან Xcode-ის ბილდის სისტემა პროექტის ყველა პროდუქტს ერთსა და იმავე საქაღალდეში ათავსებს derived data-ში, სამიზნეებს შეიძლება შეეძლოთ ისეთი პროდუქტების იმპორტი, რომლებიც არ უნდა იმპორტირდეს. კომპილაციები შეიძლება ჩავარდეს CI-ზე, სადაც სუფთა ბილდები უფრო ხშირია, ან მოგვიანებით, როდესაც სხვა კონფიგურაცია გამოიყენება.
- სამიზნის ტრანზიტული დინამიური დამოკიდებულებები უნდა დაკოპირდეს ნებისმიერ საქაღალდეში, რომელიც შედის `LD_RUNPATH_SEARCH_PATHS` ბილდის პარამეტრში. თუ ეს არ გაკეთდა, სამიზნე ვერ შეძლებს მათ პოვნას შესრულების დროს. ეს ადვილია გასააზრებლად და დასაყენებლად, როდესაც გრაფი მცირეა, მაგრამ პრობლემა ხდება გრაფის ზრდასთან ერთად.
- როდესაც სამიზნე აკავშირებს სტატიკურ [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)-ს, მას სჭირდება დამატებითი ბილდის ფაზა, რათა Xcode-მა დაამუშაოს ბანდი და ამოიღოს შესაბამისი ბინარი მიმდინარე პლატფორმისა და არქიტექტურისთვის. ეს ბილდის ფაზა ავტომატურად არ ემატება და მისი დამატება ადვილად შეიძლება დაგავიწყდეთ.

ზემოთ ჩამოთვლილი მხოლოდ რამდენიმე მაგალითია, მაგრამ წლების განმავლობაში ბევრი სხვაც შეგვხვედრია. წარმოიდგინეთ, რომ დამოკიდებულების გრაფის შენარჩუნება და მისი ვალიდურობის უზრუნველყოფა ინჟინრების გუნდს დაეკისროს. ან კიდევ უარესი, რომ ეს სირთულეები ბილდის დროს გადაწყდებოდეს დახურული კოდის მქონე ბილდის სისტემით, რომლის კონტროლი ან მორგებაც შეუძლებელია. ნაცნობია? ეს არის მიდგომა, რომელიც Apple-მა აირჩია Xcode-სა და XcodeProj-ში და რომელიც Swift Package Manager-მა მემკვიდრეობით მიიღო.

ჩვენ მტკიცედ გვჯერა, რომ დამოკიდებულების გრაფი უნდა იყოს **ცხადი** და **სტატიკური**, რადგან მხოლოდ ასე შეიძლება მისი **ვალიდაცია** და **ოპტიმიზაცია**. Tuist-ით თქვენ ფოკუსირდებით იმაზე, თუ რა რაზეა დამოკიდებული, ხოლო დანარჩენზე ჩვენ ვზრუნავთ. სირთულეები და იმპლემენტაციის დეტალები თქვენგან აბსტრაქირებულია.

შემდეგ სექციებში ისწავლით, როგორ განაცხადოთ დამოკიდებულებები თქვენს პროექტში.

> [!TIP]
> **გრაფის ვალიდაცია**
>
> Tuist ახდენს გრაფის ვალიდაციას პროექტის გენერაციის დროს, რათა დარწმუნდეს, რომ არ არსებობს ციკლები და ყველა დამოკიდებულება ვალიდურია. ამის წყალობით, ნებისმიერ გუნდს შეუძლია მიიღოს მონაწილეობა დამოკიდებულების გრაფის განვითარებაში მისი დაზიანების შიშის გარეშე.


## ლოკალური დამოკიდებულებები {#local-dependencies}

სამიზნეებს შეუძლიათ იყვნენ დამოკიდებულნი სხვა სამიზნეებზე იმავე და სხვა პროექტებში, ასევე ბინარებზე. `Target`-ის ინსტანციაციისას, შეგიძლიათ გადასცეთ `dependencies` არგუმენტი შემდეგი ვარიანტებიდან ნებისმიერით:

- `Target`: აცხადებს დამოკიდებულებას იმავე პროექტის შიგნით არსებულ სამიზნესთან.
- `Project`: აცხადებს დამოკიდებულებას სხვა პროექტში არსებულ სამიზნესთან.
- `Framework`: აცხადებს დამოკიდებულებას ბინარულ ფრეიმვორკთან.
- `Library`: აცხადებს დამოკიდებულებას ბინარულ ბიბლიოთეკასთან.
- `XCFramework`: აცხადებს დამოკიდებულებას ბინარულ XCFramework-თან.
- `SDK`: აცხადებს დამოკიდებულებას სისტემურ SDK-თან.
- `XCTest`: აცხადებს დამოკიდებულებას XCTest-თან.
- `Macro`: აცხადებს დამოკიდებულებას Swift macro სამიზნესთან, რომელიც განსაზღვრულია იმავე პროექტში (იხილეთ [Swift Macros](#swift-macros)).

> [!NOTE]
> **დამოკიდებულების პირობები**
>
> დამოკიდებულების ყველა ტიპი იღებს `condition` ოფციას დამოკიდებულების პირობითად დასაკავშირებლად პლატფორმის მიხედვით. ნაგულისხმევად, ის აკავშირებს დამოკიდებულებას ყველა იმ პლატფორმისთვის, რომელსაც სამიზნე მხარდაჭერს.


## გარე დამოკიდებულებები {#external-dependencies}

Tuist ასევე გაძლევთ საშუალებას განაცხადოთ გარე დამოკიდებულებები თქვენს პროექტში.

### Swift Packages {#swift-packages}

Swift Packages არის ჩვენს მიერ რეკომენდებული გზა პროექტში დამოკიდებულებების განსაცხადებლად. მათი ინტეგრირება შეგიძლიათ Xcode-ის ნაგულისხმევი ინტეგრაციის მექანიზმით ან Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით.

#### Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია {#tuists-xcodeprojbased-integration}

Xcode-ის ნაგულისხმევი ინტეგრაცია, მიუხედავად იმისა, რომ ყველაზე მოსახერხებელია, არ აკმაყოფილებს მოქნილობისა და კონტროლის მოთხოვნებს, რაც საჭიროა საშუალო და დიდი პროექტებისთვის. ამის გადასალახად, Tuist გთავაზობთ XcodeProj-ზე დაფუძნებულ ინტეგრაციას, რომელიც საშუალებას გაძლევთ ინტეგრირება გაუკეთოთ Swift Packages-ს თქვენს პროექტში XcodeProj-ის სამიზნეების გამოყენებით. ამის წყალობით, ჩვენ არა მხოლოდ გაძლევთ მეტ კონტროლს ინტეგრაციაზე, არამედ თავსებადს ხდის მას ისეთ სამუშაო პროცესებთან, როგორიცაა <.localized_link href="/guides/features/cache">ქეშირება</.localized_link> და <.localized_link href="/guides/features/selective-testing">სელექციური ტესტების გაშვება</.localized_link>.

XcodeProj-ის ინტეგრაციას, სავარაუდოდ, მეტი დრო დასჭირდება ახალი Swift Package ფუნქციების მხარდასაჭერად ან მეტი პაკეტის კონფიგურაციების დასამუშავებლად. თუმცა, Swift Packages-სა და XcodeProj სამიზნეებს შორის მითითების ლოგიკა ღია კოდია და საზოგადოებას შეუძლია მასში წვლილის შეტანა. ეს ეწინააღმდეგება Xcode-ის ნაგულისხმევ ინტეგრაციას, რომელიც დახურული კოდია და Apple-ის მიერ მხარდაჭერილი.

გარე დამოკიდებულებების დასამატებლად, უნდა შექმნათ `Package.swift` ან `Tuist/` საქაღალდეში, ან პროექტის ფესვში.

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
> `PackageSettings` ეგზემპლარი, რომელიც ჩასმულია კომპილატორის დირექტივაში, საშუალებას გაძლევთ დააკონფიგურიროთ, თუ როგორ ხდება პაკეტების ინტეგრაცია. მაგალითად, ზემოთ მოცემულ მაგალითში ის გამოიყენება პაკეტებისთვის ნაგულისხმევი პროდუქტის ტიპის გადასაფარად. ნაგულისხმევად, ის არ გჭირდებათ. ასევე შეგიძლიათ გამოიყენოთ ის SwiftPM ბინარული სამიზნეების მოსალოდნელი ხელმოწერების კონფიგურირებისთვის `expectedSignatures`-ის მეშვეობით.


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
> თუ თქვენი პროექტი იყენებს მორგებულ ბილდის კონფიგურაციებს (კონფიგურაციები, განსხვავებული სტანდარტული `Debug`-სა და `Release`-გან), უნდა მიუთითოთ ისინი `PackageSettings`-ში `baseSettings`-ის გამოყენებით. გარე დამოკიდებულებებს სჭირდებათ ცოდნა თქვენი პროექტის კონფიგურაციების შესახებ, რათა სწორად ააწყონ. მაგალითად:
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

`Package.swift` ფაილი მხოლოდ ინტერფეისია გარე დამოკიდებულებების განსაცხადებლად, არაფერი მეტი. ამიტომაც არ განსაზღვრავთ პაკეტში რაიმე სამიზნეს ან პროდუქტს. როდესაც დამოკიდებულებები განსაზღვრული გაქვთ, შეგიძლიათ შეასრულოთ შემდეგი ბრძანება დამოკიდებულებების გადასაწყვეტად და `Tuist/Dependencies` საქაღალდეში ჩასატანად:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

როგორც შეიძლება შენიშნეთ, ჩვენ ვიყენებთ [CocoaPods](https://cocoapods.org)-ის მსგავს მიდგომას, სადაც დამოკიდებულებების გადაწყვეტა ცალკე ბრძანებაა. ეს მომხმარებლებს აძლევს კონტროლს იმაზე, თუ როდის სურთ დამოკიდებულებების გადაწყვეტა და განახლება, და საშუალებას აძლევს გახსნან პროექტი Xcode-ში ისე, რომ ის მზად იყოს კომპილაციისთვის. ჩვენ გვჯერა, რომ ეს არის ის სფერო, სადაც Apple-ის Swift Package Manager-თან ინტეგრაციით უზრუნველყოფილი დეველოპერული გამოცდილება დროთა განმავლობაში, პროექტის ზრდასთან ერთად, უარესდება.

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

როდესაც ახდენთ Swift Macro-ს ან Build Tool Plugin-ის ინტეგრაციას გარე Swift Package-დან Xcode-ის ნაგულისხმევი ინტეგრაციის მეშვეობით, განაცხადეთ ის შესაბამისად `.macro` და `.plugin` ტიპებით. მაკროების მოხმარება ასევე შესაძლებელია [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციის](#tuists-xcodeprojbased-integration) მეშვეობით, ხოლო თუ გსურთ საკუთარი Swift macro-ს განსაზღვრა პაკეტიდან მოხმარების ნაცვლად, იხილეთ [Swift Macros](#swift-macros).

> [!WARNING]
> **SPM build tool plugins**
>
> SPM build tool plugins უნდა განაცხადოთ [Xcode-ის ნაგულისხმევი ინტეგრაციის](#xcodes-default-integration) მექანიზმის გამოყენებით, მაშინაც კი, თუ თქვენი პროექტის დამოკიდებულებებისთვის იყენებთ Tuist-ის [XcodeProj-ზე დაფუძნებულ ინტეგრაციას](#tuists-xcodeprojbased-integration).

SPM build tool plugins არის Swift პროგრამები, რომლებსაც Xcode და SwiftPM ასრულებენ, რათა აღმოაჩინონ კონკრეტული ბილდის ბრძანებები, რომლებიც სამიზნისთვის უნდა შესრულდეს. ეს ბრძანებები შეიძლება დამოკიდებული იყოს პაკეტის გრაფზე, სამიზნის ფაილებზე, პლაგინის სამუშაო დირექტორიაზე, გადაწყვეტილ პლაგინის ინსტრუმენტებზე და პლაგინის მიერ განცხადებულ გამოსავალზე. ზოგიერთი პლაგინი ასევე ქმნის ფაილებს, რომლებიც უნდა გახდნენ იმავე სამიზნის ბილდის ნაწილი.

Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაცია ასახავს პაკეტის პროდუქტებს ნატიურ Xcode სამიზნეებში, როდესაც ასახვა სტატიკურია, მაგალითად ბიბლიოთეკები, ბინარები, შესრულებადი ფაილები და მაკროები. Build tool plugins-ს არ გააჩნია ეკვივალენტური ნატიური Xcode პროექტის პრიმიტივი Xcode-ის SwiftPM ინტეგრაციის გარეთ. მიუხედავად იმისა, რომ პლაგინს საბოლოოდ შეუძლია შესრულებადი ფაილის გაშვება, ამ შესრულებადი ფაილის ჩვეულებრივი სკრიპტის ბილდის ფაზიდან გამოძახება არ არის ეკვივალენტური პლაგინის გაშვებისა: Tuist-ს ჯერ უნდა შეაფასოს პლაგინის Swift კოდი, აღადგინოს SwiftPM-ის პლაგინის კონტექსტი, აღმოაჩინოს ბრძანებები, მოდელირება გაუკეთოს განცხადებულ შეყვანებსა და გამოსავალს და დაამატოს ნებისმიერი გენერირებული ფაილი სამიზნის გრაფში, სანამ Xcode დაგეგმავს ბილდს.

ამ მიზეზით, პლაგინის პაკეტის მხოლოდ `Tuist/Package.swift`-ში განცხადება და მისი `.external(name:)`-ის მეშვეობით მოხმარება მხარდაჭერილი არ არის. მხარდაჭერილი ალტერნატივაა პაკეტის განცხადება `Project.packages`-ში და პლაგინის პროდუქტის დამატება მომხმარებელ სამიზნეში `.package(product:type: .plugin)`-ის გამოყენებით. ეს ინარჩუნებს პლაგინს მიბმულს გენერირებულ Xcode პროექტთან, როგორც Swift Package პროდუქტის დამოკიდებულებას, რათა Xcode-მა და SwiftPM-მა შეძლოს მისი გაშვება ნატიური პლაგინის კონტექსტით.

კომპრომისი ის არის, რომ Xcode ფლობს ამ პლაგინის ინტეგრაციას:

- Xcode წყვეტს და აწყობს პლაგინის პაკეტს თავისი SwiftPM ინტეგრაციის მეშვეობით.
- პაკეტი ჩნდება გენერირებულ პროექტში, როგორც Swift Package მითითება Tuist-ის მიერ გენერირებული გარე სამიზნის ნაცვლად.
- Tuist-ს არ შეუძლია პლაგინს მიაწოდოს იმავე დონის კონტროლი, ვალიდაცია, ქეშირება და შერჩევითი ტესტირების ქცევა, რასაც ის უზრუნველყოფს სტატიკურად ასახული პაკეტის პროდუქტებისთვის.
- CI და ლოკალურ ბილდებს უნდა ჰქონდეთ Xcode-ის პაკეტის გადაწყვეტის უფლება ამ პლაგინის პაკეტებისთვის.

ამ შედეგების გამო, ჩვენ ზოგადად არ ვუწევთ რეკომენდაციას SPM build tool plugins-ის გამოყენებას Tuist პროექტებში. როდესაც შესაძლებელია, უპირატესობა მიანიჭეთ სამიზნეში განცხადებულ ბილდის ფაზის სკრიპტს, ან გაუშვით ინსტრუმენტი სკრიპტიდან გენერირებული Xcode პროექტის გარეთ, სანამ Tuist-ს ან Xcode-ს გამოიძახებთ.

SPM build tool plugin-ის პრაქტიკული გამოყენებაა კოდის ლინტინგის შესრულება Xcode-ის "Run Build Tool Plug-ins" ბილდის ფაზის დროს. Xcode პროექტის გენერირებისთვის build tool plugin-ის შენარჩუნებით, განაცხადეთ პაკეტი პროექტის მანიფესტის `packages` მასივში და შემდეგ ჩართეთ პაკეტი ტიპით `.plugin` სამიზნის დამოკიდებულებებში.

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

ვინაიდან [Carthage](https://github.com/carthage/carthage) გამოაქვს `frameworks` ან `xcframeworks`, შეგიძლიათ შეასრულოთ `carthage update` დამოკიდებულებების `Carthage/Build` დირექტორიაში გამოსატანად და შემდეგ გამოიყენოთ `.framework` ან `.xcframework` სამიზნის დამოკიდებულების ტიპი თქვენს სამიზნეში დამოკიდებულების განსაცხადებლად. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **აწყობა და ტესტირება**
>
> თუ თქვენს პროექტს აწყობთ და ტესტავთ `xcodebuild build` და `tuist test`-ის მეშვეობით, ასევე დაგჭირდებათ Carthage-ით გადაწყვეტილი დამოკიდებულებების არსებობის უზრუნველყოფა `carthage update` ბრძანების შესრულებით აწყობამდე ან ტესტირებამდე.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) მოითხოვს Xcode პროექტს დამოკიდებულებების ინტეგრაციისთვის. შეგიძლიათ გამოიყენოთ Tuist პროექტის გენერაციისთვის და შემდეგ შეასრულოთ `pod install` დამოკიდებულებების ინტეგრაციისთვის workspace-ის შექმნით, რომელიც შეიცავს თქვენს პროექტს და Pods დამოკიდებულებებს. შეგიძლიათ ეს ჩასვათ სკრიპტში, რომლის გაშვებაც პროექტის გენერაციამდე შეგიძლიათ.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods დამოკიდებულებები არ არის თავსებადი ისეთ სამუშაო ნაკადებთან, როგორიცაა `build` ან `test`, რომლებიც ასრულებენ `xcodebuild`-ს პროექტის გენერაციის შემდეგ მაშინვე. ისინი ასევე არ არის თავსებადი ბინარულ ქეშირებასთან და შერჩევით ტესტირებასთან, ვინაიდან თითის ანაბეჭდის ლოგიკა არ ითვალისწინებს Pods დამოკიდებულებებს.


## Swift Macros {#swift-macros}

Tuist პროექტში [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)-თან მუშაობისას არსებობს ორი განსხვავებული სცენარი და ღირს იმის ზუსტად მითითება, თუ რომელში ხართ:

- **გარე Swift Package-ში განსაზღვრული მაკროს მოხმარება.** ორივე ინტეგრაციის მექანიზმი უჭერს მხარს მაკროებს. [Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით](#tuists-xcodeprojbased-integration), თქვენ განაცხადებთ პაკეტს `Tuist/Package.swift`-ში და ეყრდნობით მას `.external(name:)`-ის მეშვეობით — Tuist ასახავს მაკროს პროდუქტს ნატიურ სამიზნეში. [Xcode-ის ნაგულისხმევი ინტეგრაციით](#xcodes-default-integration), თქვენ განაცხადებთ დამოკიდებულებას `.package(product:type: .macro)`-ით. build tool plugins-გან განსხვავებით, მაკროები არ არის შეზღუდული Xcode-ის ნაგულისხმევ ინტეგრაციაზე.
- **საკუთარი მაკროს განსაზღვრა** თქვენი პროექტის ნაწილად — მაგალითად, საერთო ბიბლიოთეკაში თქვენს მონორეპოში. ამისთვის `Package.swift` არ გჭირდებათ: Tuist-ს აქვს პირველხარისხოვანი `.macro` პროდუქტის ტიპი, ასე რომ, შეგიძლიათ მაკროს სამიზნე პირდაპირ განაცხადოთ თქვენს მანიფესტებში.

### საკუთარი მაკროს განსაზღვრა {#defining-your-own-macro}

Swift მაკრო არის კომპილატორის პლაგინი: შესრულებადი ფაილი, რომელსაც Swift კომპილატორი კომპილაციის დროს ტვირთავს და ასრულებს. Tuist ამას ნატიურად მოდელირებს `.macro` პროდუქტის ტიპით. მიუხედავად იმისა, რომ Apple Xcode პროექტებში არ წარმოადგენს Swift Macro სამიზნის ტიპს, Tuist საშუალებას გაძლევთ ამის გაკეთებისა ბრძანების ხაზის ინსტრუმენტის სამიზნის გენერირებით, მისი დაკავშირებით როგორც დამოკიდებულება იმ სამიზნეებისთვის, რომლებიც იყენებენ მაკროს, და `-load-plugin-executable` ფლაგის ჩართვით მათ Swift კომპილატორის პარამეტრებში. ყველა ეს ტექნიკური დეტალი თქვენთვის სრულდება.

ტიპური მაკრო იყოფა ორ სამიზნედ: **პლაგინის** სამიზნე, რომელიც ახორციელებს მაკროს (`product: .macro`), და **ბიბლიოთეკის** სამიზნე, რომელიც განაცხადებს მაკროს საჯარო ინტერფეისს (`@attached`/`@freestanding` განცხადებები) და ეყრდნობა პლაგინს `.macro(name:)`-ის მეშვეობით. ვინაიდან პლაგინი შესრულების მანქანაზე მუშაობს, მისი სამიზნე მხოლოდ ჰოსტისთვისაა (macOS).

მაკროს რეალიზაცია ეყრდნობა [swift-syntax](https://github.com/swiftlang/swift-syntax)-ს, რომელსაც თქვენ განაცხადებთ როგორც ჩვეულებრივ გარე დამოკიდებულებას `Tuist/Package.swift`-ში:

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

ნებისმიერ სამიზნეს, რომელიც უკავშირდება `MyLibrary`-ს, ახლა შეუძლია მაკროს გამოყენება — Tuist ავრცელებს პლაგინს, რათა კომპილატორმა შეძლოს მისი ჩატვირთვა.


## სტატიკური თუ დინამიური {#static-or-dynamic}

ჩარჩოები და ბიბლიოთეკები შეიძლება დაკავშირდეს სტატიკურად ან დინამიურად, **არჩევანი, რომელსაც მნიშვნელოვანი გავლენა აქვს ისეთ ასპექტებზე, როგორიცაა აპლიკაციის ზომა და ჩატვირთვის დრო**. მიუხედავად მისი მნიშვნელობისა, ეს გადაწყვეტილება ხშირად მიიღება დიდი განხილვის გარეშე.

**ზოგადი წესი** არის ის, რომ რილის ბილდებში რაც შეიძლება მეტი რამ უნდა იყოს სტატიკურად დაკავშირებული სწრაფი ჩატვირთვის დროის მისაღწევად, ხოლო debug ბილდებში რაც შეიძლება მეტი რამ უნდა იყოს დინამიურად დაკავშირებული სწრაფი იტერაციის დროის მისაღწევად.

პროექტის გრაფში სტატიკურ და დინამიურ დაკავშირებას შორის ცვლილების გამოწვევა Xcode-ში არ არის მარტივი, რადგან ცვლილებას კასკადური ეფექტი აქვს მთელ გრაფზე (მაგ., ბიბლიოთეკებს არ შეუძლიათ რესურსების შენახვა, სტატიკურ ჩარჩოებს ჩაშენება არ სჭირდებათ). Apple ცდილობდა პრობლემის გადაჭრას კომპილაციის დროის გადაწყვეტილებებით, როგორიცაა Swift Package Manager-ის ავტომატური არჩევანი სტატიკურ და დინამიურ დაკავშირებას შორის, ან [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). თუმცა, ეს კომპილაციის გრაფს ამატებს ახალ დინამიურ ცვლადებს, რაც ზრდის არადეტერმინიზმის წყაროებს და შესაძლოა გახადოს არასანდო ზოგიერთი ფუნქცია, როგორიცაა Swift Previews, რომელიც ეყრდნობა კომპილაციის გრაფს.

საბედნიეროდ, Tuist კონცეპტუალურად ამცირებს სტატიკურ და დინამიურს შორის ცვლილებასთან დაკავშირებულ სირთულეს და ქმნის <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>-ებს, რომლებიც სტანდარტულია დაკავშირების ტიპების მიხედვით. <.localized_link href="/guides/features/projects/dynamic-configuration">გარემოს ცვლადების მეშვეობით დინამიური კონფიგურაციების</.localized_link> კომბინაციაში, შეგიძლიათ დაკავშირების ტიპი გადასცეთ გამოძახების დროს და გამოიყენოთ მნიშვნელობა თქვენს მანიფესტებში სამიზნეების პროდუქტის ტიპის დასაყენებლად.

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

გაითვალისწინეთ, რომ Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">არ ირჩევს მოხერხებულობას არაცხადი კონფიგურაციის მეშვეობით მისი ხარჯების გამო</.localized_link>. ეს ნიშნავს, რომ ჩვენ ვეყრდნობით თქვენს მიერ დაკავშირების ტიპის და ნებისმიერი დამატებითი ბილდის პარამეტრის დაყენებას, რომლებიც ზოგჯერ საჭიროა, როგორიცაა [`-ObjC` ლინკერის ფლაგი](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), რათა დარწმუნდეთ, რომ მიღებული ბინარები სწორია. შესაბამისად, ჩვენი მიდგომაა მოგაწოდოთ რესურსები, ჩვეულებრივ დოკუმენტაციის სახით, რათა მიიღოთ სწორი გადაწყვეტილებები.

> [!TIP]
> **მაგალითი: The Composable Architecture**
>
> Swift Package, რომელსაც ბევრი პროექტი ინტეგრირებს, არის [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). იხილეთ მეტი დეტალი [ამ სექციაში](#the-composable-architecture).


### სცენარები {#scenarios}

არსებობს სცენარები, სადაც დაკავშირების მთლიანად სტატიკურად ან დინამიურად დაყენება არ არის შესაძლებელი ან კარგი იდეა. ქვემოთ მოცემულია არასრული სია სცენარებისა, სადაც შეიძლება დაგჭირდეთ სტატიკური და დინამიური დაკავშირების შერევა:

- **აპლიკაციები გაფართოებებით:** ვინაიდან აპლიკაციებს და მათ გაფართოებებს კოდის გაზიარება სჭირდებათ, შეიძლება დაგჭირდეთ ამ სამიზნეების დინამიურად გახდომა. წინააღმდეგ შემთხვევაში, ერთი და იგივე კოდი გაორმაგდება როგორც აპლიკაციაში, ისე გაფართოებაში, რაც გაზრდის ბინარის ზომას.
- **წინასწარ კომპილირებული გარე დამოკიდებულებები:** ზოგჯერ მოწოდებული ხართ წინასწარ კომპილირებული ბინარებით, რომლებიც არის სტატიკური ან დინამიური. სტატიკური ბინარები შეიძლება გახვეული იყოს დინამიურ ჩარჩოებში ან ბიბლიოთეკებში დინამიურად დასაკავშირებლად.

გრაფში ცვლილებების შეტანისას, Tuist გააანალიზებს მას და გამოაჩენს გაფრთხილებას, თუ აღმოაჩენს „სტატიკურ გვერდით ეფექტს“. ეს გაფრთხილება მიზნად ისახავს დაგეხმაროთ პრობლემების იდენტიფიცირებაში, რომლებიც შეიძლება წარმოიშვას სამიზნის სტატიკურად დაკავშირებიდან, რომელიც ტრანზიტულად ეყრდნობა სტატიკურ სამიზნეს დინამიური სამიზნეების მეშვეობით. ეს გვერდითი ეფექტები ხშირად ვლინდება ბინარის ზომის ზრდით ან, უარეს შემთხვევაში, შესრულების დროს კრახებით.

## პრობლემების გადაჭრა {#troubleshooting}

### Objective-C დამოკიდებულებები {#objectivec-dependencies}

Objective-C დამოკიდებულებების ინტეგრაციისას, მომხმარებელ სამიზნეზე გარკვეული ფლაგების ჩართვა შეიძლება იყოს აუცილებელი შესრულების დროს კრახების თავიდან ასაცილებლად, როგორც დეტალურად არის აღწერილი [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)-ში.

ვინაიდან ბილდის სისტემას და Tuist-ს არ აქვს ფლაგის აუცილებლობის დადგენის გზა, და ვინაიდან ფლაგს თან ახლავს პოტენციურად არასასურველი გვერდითი ეფექტები, Tuist არ გამოიყენებს ამ ფლაგებს ავტომატურად, და ვინაიდან Swift Package Manager განიხილავს `-ObjC`-ს, როგორც ჩართულს `.unsafeFlag`-ის მეშვეობით, უმეტეს პაკეტს არ შეუძლია მისი ჩართვა ნაგულისხმევ დაკავშირების პარამეტრებში, როცა ეს საჭიროა.

Objective-C დამოკიდებულებების მომხმარებლებმა (ან შიდა Objective-C სამიზნეებმა) უნდა გამოიყენონ `-ObjC` ან `-force_load` ფლაგები, როცა ეს საჭიროა, მომხმარებელ სამიზნეებზე `OTHER_LDFLAGS`-ის დაყენებით.

### Firebase და სხვა Google ბიბლიოთეკები {#firebase-other-google-libraries}

Google-ის ღია კოდის ბიბლიოთეკები — მიუხედავად მათი სიმძლავრისა — შეიძლება რთული იყოს Tuist-ში ინტეგრირება, რადგან ისინი ხშირად იყენებენ არასტანდარტულ არქიტექტურას და ტექნიკებს აგების პროცესში.

აქ არის რამდენიმე რჩევა, რომლის დაცვაც შეიძლება იყოს აუცილებელი Firebase-ის და Google-ის სხვა Apple-პლატფორმის ბიბლიოთეკების ინტეგრირებისთვის:

#### დარწმუნდით, რომ `-ObjC` დაემატა `OTHER_LDFLAGS`-ს {#ensure-objc-is-added-to-other_ldflags}

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

დამატებითი დეტალებისთვის იხილეთ ზემოთ მოცემული განყოფილება [Objective-C დამოკიდებულებები](#objectivec-dependencies).

#### `FBLPromises`-ის პროდუქტის ტიპის დაყენება დინამიურ ფრეიმვორკად {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Google-ის გარკვეული ბიბლიოთეკები დამოკიდებულია `FBLPromises`-ზე, რომელიც ასევე Google-ის ბიბლიოთეკაა. შეიძლება წააწყდეთ კრახს, რომელიც ახსენებს `FBLPromises`-ს და გამოიყურება დაახლოებით ასე:

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

როგორც აღწერილია [აქ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) და [გაუმართავობის აღმოფხვრის განყოფილებაში](#troubleshooting), პაკეტების სტატიკურად დაკავშირებისას (რაც Tuist-ის ნაგულისხმევი დაკავშირების ტიპია) დაგჭირდებათ `OTHER_LDFLAGS` აგების პარამეტრის დაყენება `$(inherited) -ObjC`-ზე. ალტერნატიულად, შეგიძლიათ გადააწეროთ პაკეტის პროდუქტის ტიპი, რომ ის იყოს დინამიური. სტატიკურად დაკავშირებისას, ტესტის და აპლიკაციის სამიზნეები ჩვეულებრივ მუშაობენ პრობლემების გარეშე, მაგრამ SwiftUI პრევიუები გაფუჭებულია. ეს შეიძლება მოგვარდეს ყველაფრის დინამიურად დაკავშირებით. ქვემოთ მოცემულ მაგალითში [Sharing](https://github.com/pointfreeco/swift-sharing) ასევე დამატებულია როგორც დამოკიდებულება, რადგან ის ხშირად გამოიყენება The Composable Architecture-თან ერთად და აქვს საკუთარი [კონფიგურაციის ხაფანგები](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

შემდეგი კონფიგურაცია ყველაფერს დააკავშირებს დინამიურად — შესაბამისად, აპლიკაციის + ტესტის სამიზნეები და SwiftUI პრევიუები იმუშავებენ.

> [!TIP]
> **სტატიკური თუ დინამიური**
>
> დინამიური დაკავშირება არ არის ყოველთვის რეკომენდებული. დამატებითი დეტალებისთვის იხილეთ განყოფილება [სტატიკური თუ დინამიური](#static-or-dynamic). ამ მაგალითში, სიმარტივისთვის, ყველა დამოკიდებულება დაკავშირებულია დინამიურად პირობების გარეშე.


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

როდესაც დინამიური ფრეიმვორკი ან ბიბლიოთეკა დამოკიდებულია სტატიკურებზე `import StaticSwiftModule`-ის მეშვეობით, სიმბოლოები შედიან დინამიური ფრეიმვორკის ან ბიბლიოთეკის `.swiftmodule`-ში, რამაც შესაძლოა <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">გამოიწვიოს კომპილაციის ჩავარდნა</.localized_link>. ამის თავიდან ასაცილებლად, სტატიკური დამოკიდებულება უნდა შემოიტანოთ <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>-ის გამოყენებით:

```swift
internal import StaticModule
```

> [!NOTE]
> იმპორტებზე წვდომის დონე ჩართულია Swift 6-ში. თუ იყენებთ Swift-ის უფრო ძველ ვერსიებს, უნდა გამოიყენოთ <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>:


```swift
@_implementationOnly import StaticModule
```

## დაკავშირებული {#related}

წაიკითხეთ [როგორ მიიღო monday.com-მა მოდულარული პროექტის გრაფი Tuist-ით](https://tuist.dev/customers/monday), დაწყებული იმ სამიზნეებით, რომლებსაც ყველაზე ნაკლები დამოკიდებულება აქვთ.
