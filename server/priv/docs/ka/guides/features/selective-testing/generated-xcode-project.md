---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · შერჩევითი ტესტირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით მხოლოდ ის Xcode და გენერირებული პროექტის ტესტები, რომლებზეც თქვენი უახლესი ცვლილებები აისახა, Tuist-ის შერჩევითი ტესტირების მეშვეობით, რათა უწყვეტ ინტეგრაციას უკუკავშირი წამებში მიეწოდოს."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project}

როგორც პროექტი იზრდება, ყოველ გაშვებაზე ყველა ტესტის შესრულება მასშტაბირებადობას კარგავს. Tuist-ის შერჩევითი ტესტირება ასრულებს მხოლოდ იმ ტესტებს, რომელთა სამიზნეები შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ, Tuist-ის <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმის</.localized_link> საფუძველზე.

შერჩევითად ტესტების გასაშვებად თქვენს <.localized_link href="/guides/features/projects">გენერირებულ პროექტთან</.localized_link>, გამოიყენეთ `tuist test` ბრძანება. ბრძანება <.localized_link href="/guides/features/projects/hashing">აჰეშირებს</.localized_link> თქვენს პროექტს ისევე, როგორც <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშისთვის</.localized_link>, და წარმატების შემთხვევაში ინახავს ჰეშებს, რათა მომავალ გაშვებებში განსაზღვროს, რა შეიცვალა. მომავალ გაშვებებში, `tuist test` გამჭვირვალედ იყენებს ჰეშებს ტესტების ფილტრაციისთვის და ასრულებს მხოლოდ მათ, რომლებიც შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ.

`tuist test` პირდაპირ ინტეგრირდება <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშთან</.localized_link>, რათა გამოიყენოს მაქსიმალურად ბინარული ფაილები თქვენი ადგილობრივი ან დისტანციური საცავიდან და შეამციროს ბილდის დრო თქვენი ტესტების სუიტის გაშვებისას. შერჩევითი ტესტირებისა და მოდულის ქეშირების კომბინაციამ შეიძლება დრამატულად შეამციროს დრო, რომელიც სჭირდება ტესტების გაშვებას თქვენს CI-ზე.

თუ თქვენი ტესტები მხოლოდ სიმულატორის მიზნებს (targets) ეხება, გადაეცით `--destination simulator`, რათა `tuist test` გამოიყენოს და ჩამოტვირთოს მხოლოდ ქეშირებული ბინარული ფაილების სიმულატორის ნაწილები. იხილეთ <.localized_link href="/guides/features/cache/module-cache#destination-selection">დანიშნულების არჩევა</.localized_link>. შერჩევითი ტესტირების ჰეშები იგივეა ყოველი `--destination` მნიშვნელობისთვის.

## ბილდისა და ტესტირების ცალკეული სამუშაოები {#separate-build-and-test-jobs}

შერჩევითი ტესტირება უჭერს მხარს ბილდისა და ტესტირების ცალკეულ სამუშაოებს. გაუშვით `tuist test --build-only` ბილდის სამუშაოში, რათა Tuist-მა შეინახოს `selective-testing-graph.json` ფაილი ბილდის მიერ გამოცემული პროდუქტების გვერდით. ეს გრაფი შეიცავს ჰეშებს, რომლებიც საჭიროა შერჩევითი ტესტირებისთვის, ამიტომ ტესტირების სამუშაოს არ სჭირდება პროექტის ხელახლა გენერირება ან Swift Package დამოკიდებულებების გადაწყვეტა იმის დასადგენად, თუ რომელი მიზნები (targets) უნდა გაეშვას.

Tuist წერს გრაფს ორ ადგილას `--build-only`-ის დროს:

- `.xctestproducts` ბანდლის შიგნით, როდესაც გადასცემთ `-testProductsPath`-ს.
- ყოველი `.xctestrun` ფაილის გვერდით მიღებული მონაცემების `Build/Products/` დირექტორიაში.

შეინახეთ ნებისმიერი ეს გამომავალი მონაცემი აგებული პროდუქტების გვერდით და გადაეცით იგივე გზა `--without-building`-ს ტესტირების სამუშაოში. ორივე ფორმა მუშაობს:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

როდესაც Tuist ვერ პოულობს ამ გრაფს შეყვანის მონაცემების გვერდით (მაგალითად, როდესაც ბილდის სამუშაომ გამოიყენა ჩვეულებრივი `xcodebuild build-for-testing` ნაცვლად `tuist test --build-only`-ის), ის ბრუნდება პროექტის ხელახლა გენერირებაზე, რათა მაინც გამოთვალოს დაზარალებული მიზნები (targets). ამ ალტერნატიულ გზას სჭირდება Swift Package დამოკიდებულებების გადაწყვეტა ტესტირების სამუშაოზე, ამიტომ ჯერ გაუშვით `tuist install` ან შეინახეთ `Tuist/.build` ქეშში სამუშაოებს შორის.

გრაფი ასახავს წყაროს ხეს ისე, როგორიც ის იყო ბილდის დროს. გაუშვით ტესტირების სამუშაო იგივე კომიტზე, რაზეც ბილდის სამუშაო — თუ წყარო განსხვავდება ამ ორს შორის, ჰეშები აღარ ემთხვევა წყაროს და შერჩევითი ტესტირება შეიძლება გამოტოვოს ტესტები, რომლებიც რეალურად ჩავარდებოდა ახალ წყაროზე.

### რომელი ფლაგი უნდა გამოვიყენო? {#which-flag-should-i-use}

`.xctestrun` და `.xctestproducts` არის Xcode-ის ორი განსხვავებული გამომავალი ფორმატი და ისინი წონასწორობას აკეთებენ პორტაბელურობასა და პაიპლაინის მოხერხებულობას შორის:

- **`-testProductsPath` (`.xctestproducts`) — რეკომენდებულია ახალი პაიპლაინებისთვის.** ეს არის თვითკმარი დირექტორია: აგებული `.xctest` ბინარული ფაილები და მათი `.xctestrun` ფაილები მდებარეობენ მის შიგნით ისე, რომ გზები ფარდობითია ბანდლის ფესვთან მიმართებაში, ამიტომ ის ძალაში რჩება ნებისმიერ ადგილას, სადაცაც არ უნდა აღმოჩნდეს.
- **`-xctestrun` (ნედლი `.xctestrun`) — გამოიყენეთ, თუ უკვე გაქვთ პაიპლაინი, აგებული მიღებული მონაცემების (derived data) გარშემო.** `xcodebuild build-for-testing` წერს `.xctestrun`-ს `<derivedData>/Build/Products/`-ის თავში ნაგულისხმევად და მიუთითებს ტესტების ბანდლებზე, რომლებიც მდებარეობენ ამ ხის სხვა ადგილას. მისი ხელახლა გამოყენება სხვა სამუშაოში ნიშნავს `Build/Products/`-ში გზების უცვლელად შენარჩუნებას.

თუ ახალს იწყებთ, უპირატესობა მიანიჭეთ `-testProductsPath`-ს. თუ Tuist-ს აკავშირებთ არსებულ პაიპლაინთან, რომელიც უკვე ინახავს მიღებულ მონაცემებს (derived data) ქეშში, `-xctestrun` იღებს იგივე სწრაფ გზას, იმ პირობით, რომ ბილდის სამუშაო გადის `tuist test --build-only`-ის მეშვეობით.

ნებისმიერი შეყვანის რეჟიმია ურთიერთგამომრიცხავი `-workspace`/`-project`/`-scheme`-თან, ამიტომ Tuist ტოვებს ამ ფლაგებს, როდესაც გადამავალი არგუმენტები შეიცავს `-xctestrun`-ს ან `-testProductsPath`-ს, და გადასცემს შერჩეულ მიზნებს (targets) `-only-testing`-ის მეშვეობით.

> [!WARNING]
> **მოდულის vs ფაილის დონის გრანულარობა**
>
> ტესტებსა და წყაროებს შორის კოდში არსებული დამოკიდებულებების აღმოჩენის შეუძლებლობის გამო, ნაგულისხმევი შერჩევითი ტესტირების მაქსიმალური გრანულარობა არის მიზნის (target) დონეზე. [დაფარვის სტრატეგია](#coverage-based-test-selection) ამცირებს მას ცალკეულ ტესტებამდე. ამიტომ, ჩვენ გირჩევთ, შეინარჩუნოთ თქვენი მიზნები (targets) მცირე და ფოკუსირებული, რათა მაქსიმალურად გამოიყენოთ შერჩევითი ტესტირების უპირატესობები.


## დაფარვაზე დაფუძნებული ტესტების შერჩევა {#coverage-based-test-selection}

> [!NOTE]
> **ადრეული წვდომა**
>
> დაფარვაზე დაფუძნებული ტესტების შერჩევა არის ადრეული წვდომის ეტაპზე. დაგვიკავშირდით, რათა ჩავრთოთ ის თქვენს ანგარიშზე. სანამ ის ჩართული არ იქნება, სტრატეგია იქცევა როგორც ნაგულისხმევი შერჩევითი ტესტირება.

ნაგულისხმევად, შერჩევითი ტესტირება ტოვებს მთლიან სატესტო მიზნებს (test targets), რომელთა ჰეშიც უკვე გაიარა. `.coverage()` სტრატეგია მიდის უფრო შორს: დარჩენილ სატესტო მიზნებში, ის ასევე ტოვებს იმ ტესტებს, რომელთა კოდის დაფარვაც ადრეულ გაშვებაზე არ მოიცავდა თქვენი ცვლილების მიერ შეხებულ ფაილებს. ის მუშაობს XCTest და XCUITest ტესტებთან, ასევე [Swift Testing](#swift-testing) ტესტებთან სუიტებში, რომლებიც მისთვის არის მომზადებული. ჩართეთ ის `Tuist.swift`-ში:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

სტრატეგია მოითხოვს:

- **დაფარვის ატვირთვებს.** Tuist ირჩევს ტესტებს იმ დაფარვის მიხედვით, რომელიც ადრეულმა გაშვებებმა ატვირთეს, ამიტომ `tuist test` ვერ ტვირთავს მანიფესტს, რომელიც აყენებს `.coverage()`-ს `upload: false`-ით.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 ან უფრო ახალი** [დაკავშირებული თქვენი სატესტო მიზნებით](#linking-testcoverageattribution). ის იწერს, თუ რომელ ფაილებს ასრულებს თითოეული ტესტი და ტოვებს იმ ტესტებს, რომლებიც Tuist-მა არ შეარჩია. მიზანი (target) მის გარეშე მხოლოდ მთლიანად შეიძლება გამოტოვებულ იქნას, როგორც ნაგულისხმევ შემთხვევაში.
- **სრული ტესტების გაშვებები, საკმარისად ხშირად.** გაშვება `tuist test --no-selective-testing`-ით ასრულებს ყველა ტესტს და ხდება საბაზისო ხაზი. შერჩევითი გაშვება ადარებს ბოლო ერთ-ერთს მისი კომიტის ისტორიაში იმავე პლატფორმაზე და არ აკეთებს დაფარვის გამოყენებას მის გარეშე. სად და რამდენად ხშირად გაუშვათ ისინი, დამოკიდებულია თქვენი გუნდის მუშაობის სტილზე, მაგალითად, თქვენი ნაგულისხმევი შტოს ყოველ კომიტზე, ყოველ ღამე ან რელიზის შტოებზე. ჩვენ გირჩევთ ნაგულისხმევ შტოს: იქ სრული გაშვება ასევე იჭერს, სანამ ცვლილება გაიგზავნება, იმას, რასაც დაფარვა ვერ ხედავს, მაგალითად, ფიქსტურას ან სერვისს, რომელზეც ტესტია დამოკიდებული.

სტრატეგიის ჩართვისას, `tuist test` ტოვებს მიზნებს (targets), რომელთა ჰეშიც უკვე გაიარა, შემდეგ კი ეკითხება Tuist-ს, თუ რომელ ტესტებს შეუძლია თქვენს ცვლილებას შეეხოს დარჩენილ მიზნებში. მიზნები (targets), რომლებსაც არ აქვთ დაზარალებული ტესტი, არ აგებენ. ახალი ტესტები, ტესტები, რომლებიც ბოლოჯერ ჩავარდა, ტესტები შეცვლილ სატესტო ფაილში და ტესტები ჩაწერილი დაფარვის გარეშე ყოველთვის სრულდება.

ზოგჯერ დაფარვა არ გამოიყენება და შედეგი ასახელებს მიზეზს: ყველა ტესტი იმ მიზნებისა (targets), რომელთა ჰეშიც არ გაიარა, სრულდება, როგორც ნაგულისხმევი შერჩევითი ტესტირების შემთხვევაში. ეს ხდება მაშინ, როდესაც არ არსებობს ბოლო საბაზისო ხაზი იმავე პლატფორმაზე, როდესაც ცვლილება ეხება 5000-ზე მეტ ფაილს, ან როდესაც შეიცვალა ფაილი, რომელმაც შეიძლება გავლენა მოახდინოს ნებისმიერ ტესტზე, მაგალითად `Package.resolved`, `Project.swift`, ან `.xcconfig`. ყველა ტესტის გასაშვებად, გადაეცით `--no-selective-testing`.

> [!NOTE]
> **ტესტების დაფარვა**
>
> დაფარვის ინსტრუმენტები, რომლებიც კითხულობენ ერთი გაშვების ანგარიშს, მათ შორის Xcode-ის, ვარაუდობენ, რომ მთელი სატესტო ნაკრები შესრულდა, ამიტომ შერჩევითი გაშვების ანგარიში გამორიცხავს გამოტოვებულ ტესტებს. Tuist-ის <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">კოდის დაფარვა</.localized_link> კი გადააქვს გამოტოვებული სატესტო მიზნების (targets) დაფარვა წინა გაშვებიდან, იყენებს <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">მიზნის დონის დაფარვას</.localized_link>, რომელსაც ის იწერს ყოველ გაშვებაზე.

### TestCoverageAttribution-ის მიერთება {#linking-testcoverageattribution}

დაამატეთ პაკეტი `Tuist/Package.swift`-ში, მიბმული მის უმცროს ვერსიაზე, რადგან 0.x უმცროსი გამოცემა შეიძლება შეცვალოს იმის ჩაწერა:

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

შემდეგ დაამატეთ ის თქვენს სატესტო მიზნებში (targets) და არასდროს აპლიკაციის მიზანში:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Tuist ნაგულისხმევად აკავშირებს პაკეტებს სტატიკურ ჩარჩოებად (static frameworks). XCTest-ის მხოლოდ მიზანი (target) არაფერს იყენებს პაკეტიდან, ამიტომ ლინკერი აგდებს მას, და მასთან ერთად ჩაწერასა და გამოტოვებას. ან დაამატეთ `-ObjC` სატესტო მიზნის `OTHER_LDFLAGS`-ში, ან დააკავშირეთ პაკეტი დინამიურად `Tuist/Package.swift`-ში:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing-ს არ აქვს დაკვირვების API, რომელსაც ბიბლიოთეკა შეუერთდება, ამიტომ მის ტესტებს სჭირდებათ TestCoverageAttribution-ის `.coverageAttribution` თვისება (trait) მათ ნაკრებზე (suite). თვისება ვრცელდება მასში ჩაბუდებულ ნაკრებებზეც. ტესტები ნაკრებებში ამის გარეშე არ იწერენ ტესტის დონის დაფარვას, ამიტომ ისინი სრულდება მაშინ, როცა მათი მიზანი (target) სრულდება.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **ტესტები არ უნდა ემთხვეოდეს ერთმანეთს.** Swift Testing ნაგულისხმევად ასრულებს პროცესის ტესტებს პარალელურად, და დაფარვის მრიცხველებს არ შეუძლიათ განასხვავონ ერთდროულად შესრულებული ტესტები, ამიტომ ეს ტესტები არ იწერენ საკუთარ დაფარვას და ყოველთვის სრულდება. `.serialized` მხოლოდ ალაგებს ნაკრების საკუთარ ტესტებს, ამიტომ ის საკმარისია მხოლოდ მაშინ, როდესაც მიზანს (target) აქვს ერთი ნაკრები. XCTest-ს არაფერი სჭირდება: პარალელური ტესტირება ასრულებს თითოეულ ტესტის ასლს საკუთარ პროცესში.
- **გამორთეთ პარალელიზაცია თითოეული სატესტო მიზნისთვის.** Xcode აყენებს პარამეტრს თითოეულ სატესტო მიზანზე (target), ამიტომ შეგიძლიათ გამორთოთ ის მხოლოდ იმ მიზნებისთვის, რომელთა შერჩევაც გსურთ ტესტის მიხედვით, და სქემის სხვა მიზნები განაგრძობენ პარალელურად მუშაობას. ცალკე სქემა არ არის საჭირო. დააყენეთ ის სატესტო მიზანზე, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, რომელიც ასევე ასრულებს ამ მიზნის XCTest ტესტებს ასლების გარეშე. Tuist-ის მიერ გენერირებული სქემები იღებენ მას პროექტის `testingOptions`-დან, გამორთულია, თუ არ შეიცავს `.parallelizable` ან `.swiftTestingOnlyParallelizable`-ს. `-parallel-testing-enabled YES` ან `NO`-ის გადაცემა `tuist test`-ზე გადაწერს ყველა მიზნის პარამეტრს ამ გაშვებისთვის.
- **გამოტოვებას სჭირდება Swift 6.3 (Xcode 26.4) ან უფრო ახალი.** თვისება აუქმებს ტესტებს, რომლებიც Tuist-მა არ შეარჩია და აღწერს მათ როგორც გამოტოვებულს. უფრო ადრეულ ვერსიებში, ტესტები მაინც იწერენ დაფარვას, მაგრამ ისინი, რომლებიც Tuist-მა არ შეარჩია, მაინც სრულდება.

### ტესტები, რომლებიც ყოველთვის სრულდება {#tests-that-always-run}

დაფარვა ხედავს მხოლოდ კოდს, რომელსაც ტესტი ასრულებს. ტესტი, რომლის რეალური შემავალი მონაცემებია ფიქსტურები, რესურსები, ქსელი ან გარემო, შეიძლება ჩავარდეს ნებისმიერი დაფარული კოდის შეცვლის გარეშე. მონიშნეთ ის როგორც არაგამოტოვებადი და ის შესრულდება მაშინაც, როცა Tuist მას არ შეარჩევს:

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

ეს მოქმედებს მხოლოდ იმ სატესტო მიზნებში (targets), რომლებიც სრულდება. მიზანი (target), რომლის ჰეშიც უკვე გაიარა, ან რომლის ტესტებიც Tuist-მა არ შეარჩია, მთლიანად გამოიტოვება და არასდროს იწყება, ამიტომ მისი არაგამოტოვებადი ტესტებიც არ სრულდება.

იხილეთ [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) ყველა პარამეტრისთვის.

### შერჩევის ინსპექტირება {#inspecting-a-selection}

ტესტების გაშვების შერჩევითი ტესტირების ჩანართი აჩვენებს, რამ შეარჩია დაფარვამ და რატომ. იგივე მონაცემები ხელმისაწვდომია CLI-დან, `--json`-ით სკრიპტინგისთვის, და აგენტებისთვის <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol სერვერის</.localized_link> საშუალებით:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

როდესაც დაფარვა არ გამოიყენება, ტესტები მაინც ითვლება როგორც დაფარვაზე დაფუძნებული შერჩევა: მათი მიზეზი ასახელებს, რატომ ვერ გადაწყვიტა დაფარვამ, მაგალითად `tracked_file_changed`.


## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git forge ინტეგრაცია საჭიროა**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, დააკავშირეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">Tuist პროექტი</.localized_link> Git forge-თან: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>, ან <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


მას შემდეგ, რაც თქვენი Tuist პროექტი დაკავშირებული იქნება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), და დაიწყებთ `tuist test`-ის გამოყენებას თქვენი CI სამუშაო ნაკადის ნაწილად, Tuist გამოაქვეყნებს კომენტარს პირდაპირ თქვენს pull/merge request-ებში, მათ შორის, რომელი ტესტები შესრულდა და რომელი გამოიტოვა: ![GitHub აპლიკაციის კომენტარი Tuist Preview ბმულით](/images/guides/features/selective-testing/github-app-comment.png)


## გამოტოვებების კვლევა დაფაზე {#investigating-misses-on-the-dashboard}

როდესაც ადრე კეშირებული სატესტო მიზანი (target) ჩანს როგორც გამოტოვება, ტესტების გაშვების გვერდზე **შერჩევითი ტესტირების** ჩანართი საშუალებას გაძლევთ ჩაუღრმავდეთ შემავალ მონაცემებს, რომლებმაც წარმოქმნეს ჰეში. სტრიქონის გაშლა აჩვენებს კომპონენტების ქვეჰეშებს — წყაროებს, დამოკიდებულებებს, გარემოს ცვლადებს, პროექტის და მიზნის პარამეტრებს, Info.plist-ს, უფლებებს, ჰედერებს და ა.შ. — რათა ზუსტად განსაზღვროთ შემავალი მონაცემი, რომელიც შეიცვალა გაშვებებს შორის.

გამოიყენეთ **Copy as JSON** ღილაკი შერჩევითი ტესტირების ბარათის თავში, რათა გაიტანოთ ყველა შერჩევითი ტესტირების მიზანი (target) მისი ჰეშით და ქვეჰეშებით. JSON-ის შედარება ორ გაშვებას შორის არის ყველაზე სწრაფი გზა იმის დასადგენად, თუ რომელი შემავალი მონაცემი შეიცვალა, როდესაც სატესტო მიზნის ჰეში შეიცვალა.
