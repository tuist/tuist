---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · შერჩევითი ტესტირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეასრულეთ მხოლოდ ის Xcode-ისა და გენერირებული პროექტის ტესტები, რომლებზეც თქვენი ბოლო ცვლილებები აისახა, Tuist Selective Testing-ის გამოყენებით, რათა უწყვეტი ინტეგრაცია (CI) შედეგებს წამებში გადმოგცეთ."
}
---
# გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

როგორც კი პროექტი იზრდება, ყოველ პუშზე ყველა ტესტის გაშვება ვეღარ მასშტაბირდება. Tuist-ის შერჩევითი ტესტირება უშვებს მხოლოდ იმ ტესტებს, რომელთა მიზნები (targets) შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ, Tuist-ის <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმზე</.localized_link> დაყრდნობით.

ტესტების შერჩევითად გასაშვებად თქვენს <.localized_link href="/guides/features/projects">გენერირებულ პროექტთან</.localized_link> ერთად, გამოიყენეთ `tuist test` ბრძანება. ბრძანება <.localized_link href="/guides/features/projects/hashing">ჰეშირებს</.localized_link> თქვენს პროექტს ისევე, როგორც <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშისთვის</.localized_link>, და წარმატების შემთხვევაში ინახავს ჰეშებს, რათა მომავალ გაშვებებში განსაზღვროს, რა შეიცვალა. მომავალ გაშვებებში, `tuist test` გამჭვირვალედ იყენებს ჰეშებს ტესტების ფილტრაციისთვის და უშვებს მხოლოდ მათ, რომლებიც შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ.

`tuist test` პირდაპირ ინტეგრირდება <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშთან</.localized_link>, რათა გამოიყენოს მაქსიმალური რაოდენობის ბინარები თქვენი ადგილობრივი ან დისტანციური საცავიდან და შეამციროს აგების დრო თქვენი ტესტების სუიტის გაშვებისას. შერჩევითი ტესტირებისა და მოდულის ქეშირების კომბინაციამ შეიძლება დრამატულად შეამციროს დრო, რომელიც სჭირდება ტესტების გაშვებას თქვენს CI-ზე.

თუ თქვენი ტესტები მხოლოდ სიმულატორების მიზნებს (targets) ეხება, გადაეცით `--destination simulator`, რათა `tuist test` გამოიყენოს და ჩამოტვირთოს მხოლოდ ქეშირებული ბინარების სიმულატორის ნაწილები. იხილეთ <.localized_link href="/guides/features/cache/module-cache#destination-selection">დანიშნულების არჩევა</.localized_link>. შერჩევითი ტესტირების ჰეშები ერთნაირია ყოველი `--destination` მნიშვნელობისთვის.

## აგებისა და ტესტირების ცალკეული სამუშაოები {#separate-build-and-test-jobs}

შერჩევითი ტესტირება მხარს უჭერს აგებისა და ტესტირების ცალკეულ სამუშაოებს. გაუშვით `tuist test --build-only` აგების სამუშაოში, რათა Tuist-მა შეინახოს `selective-testing-graph.json` ფაილი იმ პროდუქტებთან ერთად, რომლებსაც აგება გამოყოფს. ეს გრაფი შეიცავს ჰეშებს, რომლებიც საჭიროა შერჩევითი ტესტირებისთვის, ასე რომ, ტესტირების სამუშაოს არ სჭირდება პროექტის ხელახლა გენერირება ან Swift Package-ის დამოკიდებულებების გადაწყვეტა, რათა დაადგინოს, რომელი მიზნები (targets) უნდა გაუშვას.

Tuist წერს გრაფს ორ ადგილას `--build-only`-ის დროს:

- `.xctestproducts` ბანდლის შიგნით, როდესაც გადასცემთ `-testProductsPath`-ს.
- ყოველი `.xctestrun` ფაილის გვერდით, derived data-ის `Build/Products/` დირექტორიაში.

შეინახეთ ნებისმიერი ეს შედეგი აგებულ პროდუქტებთან ერთად და გადაეცით იგივე გზა `--without-building`-ს ტესტირების სამუშაოში. ორივე ფორმა მუშაობს:

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

როდესაც Tuist ვერ პოულობს ამ გრაფს შეყვანასთან ახლოს (მაგალითად, როდესაც აგების სამუშაომ გამოიყენა ჩვეულებრივი `xcodebuild build-for-testing` `tuist test --build-only`-ის ნაცვლად), ის ბრუნდება პროექტის ხელახლა გენერირებაზე, რათა მაინც გამოთვალოს დაზარალებული მიზნები (targets). ამ ალტერნატიულ ვარიანტს სჭირდება, რომ Swift Package-ის დამოკიდებულებები გადაწყვეტილი იყოს ტესტირების სამუშაოზე, ასე რომ, ჯერ გაუშვით `tuist install` ან შეინახეთ `Tuist/.build` სამუშაოებს შორის.

გრაფი ასახავს წყაროს ხეს ისე, როგორიც ის იყო აგების დროს. გაუშვით ტესტირების სამუშაო იმავე კომიტზე, რაზეც აგების სამუშაო — თუ წყარო იცვლება ორს შორის, ჰეშები აღარ ემთხვევა წყაროს და შერჩევითი ტესტირებამ შეიძლება გამოტოვოს ტესტები, რომლებიც რეალურად ჩავარდებოდა ახალ წყაროსთან.

### რომელი ფლაგი უნდა გამოვიყენო? {#which-flag-should-i-use}

`.xctestrun` და `.xctestproducts` არის Xcode-ის ორი განსხვავებული გამომავალი ფორმატი და ისინი აწონასწორებენ პორტაბელურობას პაიპლაინის მოხერხებულობასთან:

- **`-testProductsPath` (`.xctestproducts`) — რეკომენდებულია ახალი პაიპლაინებისთვის.** ეს არის თვითკმარი დირექტორია: აგებული `.xctest` ბინარები და მათი `.xctestrun` ფაილები მდებარეობს მის შიგნით ისე, რომ გზები შეფარდებითია ბანდლის ფესვთან, ასე რომ, ის რჩება ვალიდური, სადაცაც არ უნდა აღმოჩნდეს.
- **`-xctestrun` (ნედლი `.xctestrun`) — გამოიყენეთ, თუ უკვე გაქვთ პაიპლაინი, აგებული derived data-ის გარშემო.** `xcodebuild build-for-testing` წერს `.xctestrun`-ს `<derivedData>/Build/Products/`-ის თავში ნაგულისხმევად და მიუთითებს ტესტის ბანდლებზე, რომლებიც მდებარეობს ამ ხის სხვა ადგილებში. მისი ხელახლა გამოყენება სხვა სამუშაოში ნიშნავს გზების შენარჩუნებას `Build/Products/`-ში უცვლელად.

თუ ახალს იწყებთ, უპირატესობა მიანიჭეთ `-testProductsPath`-ს. თუ Tuist-ს აკავშირებთ არსებულ პაიპლაინთან, რომელიც უკვე აკეშირებს derived data-ს, `-xctestrun` იღებს იმავე სწრაფ გზას, სანამ აგების სამუშაო გადის `tuist test --build-only`-ის მეშვეობით.

ნებისმიერი შეყვანის რეჟიმი ურთიერთგამომრიცხავია `-workspace`/`-project`/`-scheme`-თან, ასე რომ, Tuist ტოვებს ამ ფლაგებს, როდესაც გადამავალი არგუმენტები შეიცავს `-xctestrun`-ს ან `-testProductsPath`-ს, და გადასცემს შერჩეულ მიზნებს (targets) `-only-testing`-ის მეშვეობით.

> [!WARNING]
> **მოდულის vs ფაილის დონის გრანულარობა**
>
> კოდში ტესტებსა და წყაროებს შორის დამოკიდებულებების აღმოჩენის შეუძლებლობის გამო, ნაგულისხმევი შერჩევითი ტესტირების მაქსიმალური გრანულარობა არის მიზნის (target) დონეზე. [დაფარვის სტრატეგია](#coverage-based-test-selection) ამცირებს მას ცალკეულ ტესტებამდე. ამიტომ, ჩვენ გირჩევთ, თქვენი მიზნები (targets) იყოს მცირე და ფოკუსირებული, რათა მაქსიმალურად გაზარდოთ შერჩევითი ტესტირების სარგებელი.


## დაფარვაზე დაფუძნებული ტესტების შერჩევა {#coverage-based-test-selection}

> [!NOTE]
> **ადრეული წვდომა**
>
> დაფარვაზე დაფუძნებული ტესტების შერჩევა არის ადრეული წვდომის ეტაპზე. დაგვიკავშირდით, რათა ჩავრთოთ ის თქვენს ანგარიშზე. სანამ ის ჩართული არ იქნება, სტრატეგია იქცევა როგორც ნაგულისხმევი შერჩევითი ტესტირება.

ნაგულისხმევად, შერჩევითი ტესტირება ტოვებს მთლიან სატესტო მიზნებს (targets), რომელთა ჰეშიც უკვე გაიარა. `.coverage()` სტრატეგია მიდის უფრო შორს: დარჩენილ სატესტო მიზნებში, ის ასევე ტოვებს იმ ტესტებს, რომელთა კოდის დაფარვაც წინა გაშვებაზე არ მოიცავდა არცერთ ფაილს, რომელსაც თქვენმა ცვლილებამ შეეხო. ის მუშაობს XCTest-ისა და XCUITest-ის ტესტებთან, და [Swift Testing](#swift-testing)-ის ტესტებთან სუიტებში, რომლებიც მისთვის არის მომზადებული. ჩართეთ ის `Tuist.swift`-ში:

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

- **დაფარვის ატვირთვას.** Tuist ირჩევს ტესტებს იმ დაფარვის მიხედვით, რომელიც წინა გაშვებებმა ატვირთეს, ასე რომ, `tuist test` ვერ ტვირთავს მანიფესტს, რომელიც აყენებს `.coverage()`-ს `upload: false`-ით.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 ან უფრო ახალი** [დაკავშირებული თქვენი სატესტო მიზნებით](#linking-testcoverageattribution). ის იწერს, თუ რომელ ფაილებს ასრულებს თითოეული ტესტი და ტოვებს იმ ტესტებს, რომლებიც Tuist-მა არ შეარჩია. მიზანი (target) მის გარეშე მხოლოდ მთლიანად ტოვდება, როგორც ნაგულისხმევია.
- **სრული ტესტების გაშვება, საკმარისად ხშირად.** გაშვება `tuist test --no-selective-testing`-ით ასრულებს ყოველ ტესტს და ხდება საბაზისო ხაზი. შერჩევითი გაშვება ადარებს ბოლო ერთს მისი კომიტის ისტორიაში იმავე პლატფორმაზე, და არ აკეთებს დაფარვას მის გარეშე. სად და რამდენად ხშირად უნდა გაუშვათ ისინი, დამოკიდებულია იმაზე, თუ როგორ მუშაობს თქვენი გუნდი, მაგალითად, თქვენი ნაგულისხმევი ბრენჩის ყოველ კომიტზე, ყოველ ღამე, ან რელიზის ბრენჩებზე. ჩვენ გირჩევთ ნაგულისხმევ ბრენჩს: სრული გაშვება იქ ასევე იჭერს, სანამ ცვლილება გაიგზავნება, იმას, რასაც დაფარვა ვერ ხედავს, მაგალითად, ფიქსტურას ან სერვისს, რომელზეც ტესტია დამოკიდებული.

სტრატეგიის ჩართვისას, `tuist test` ტოვებს მიზნებს (targets), რომელთა ჰეშიც უკვე გაიარა, შემდეგ კი ეკითხება Tuist-ს, თუ რომელ ტესტებს შეუძლია შეეხოს თქვენს ცვლილებას დარჩენილ მიზნებში. მიზნები (targets), რომლებსაც არ აქვთ დაზარალებული ტესტი, არ აგებენ. ახალი ტესტები, ტესტები, რომლებიც ბოლოს ჩავარდა, ტესტები შეცვლილ სატესტო ფაილში და ტესტები ჩაწერილი დაფარვის გარეშე ყოველთვის გადის.

ზოგჯერ დაფარვა არ გამოიყენება და შეტყობინება ხსნის მიზეზს: ყველა ტესტი იმ მიზნებისა (targets), რომელთა ჰეშიც არ გაიარა, გადის, როგორც ნაგულისხმევი შერჩევითი ტესტირების შემთხვევაში. ეს ხდება მაშინ, როდესაც არ არსებობს ბოლო დროის საბაზისო ხაზი იმავე პლატფორმაზე, როდესაც ცვლილება ეხება 5,000-ზე მეტ ფაილს, ან როდესაც შეიცვალა ფაილი, რომელსაც შეუძლია გავლენა მოახდინოს ნებისმიერ ტესტზე, მაგალითად `Package.resolved`, `Project.swift` ან `.xcconfig`. ყოველი ტესტის გასაშვებად, გადაეცით `--no-selective-testing`.

> [!NOTE]
> **ტესტების დაფარვა**
>
> დაფარვის ინსტრუმენტები, რომლებიც კითხულობენ ერთი გაშვების ანგარიშს, მათ შორის Xcode-ის, ვარაუდობენ, რომ მთელი სატესტო სუიტა გაშვებულია, ამიტომ შერჩევითი გაშვების ანგარიშიდან გამორიცხულია გამოტოვებული ტესტები. Tuist-ის <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">კოდის დაფარვა</.localized_link> კი გადააქვს გამოტოვებული სატესტო მიზნების (targets) დაფარვა წინა გაშვებიდან, იყენებს რა <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">მიზნის დონის დაფარვას</.localized_link>, რომელსაც ის იწერს ყოველ გაშვებაზე.

### TestCoverageAttribution-ის დაკავშირება {#linking-testcoverageattribution}

დაამატეთ პაკეტი `Tuist/Package.swift`-ში, მიბმული მის მცირე ვერსიაზე, რადგან 0.x მცირე რელიზმა შეიძლება შეცვალოს ჩაწერილი მონაცემები:

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

შემდეგ დაამატეთ ის თქვენს სატესტო მიზნებში (test targets) და არასდროს აპლიკაციის მიზანში (app target):

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

Tuist ნაგულისხმევად აკავშირებს პაკეტებს სტატიკურ ფრეიმვორკებად. XCTest-ის მხოლოდ მიზანი (target) არაფერს უკავშირდება პაკეტიდან, ამიტომ ლინკერი აგდებს მას, ხოლო მასთან ერთად — ჩაწერასა და გამოტოვებას. ან დაამატეთ `-ObjC` სატესტო მიზნის `OTHER_LDFLAGS`-ში, ან დააკავშირეთ პაკეტი დინამიურად `Tuist/Package.swift`-ში:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing-ს არ აქვს დაკვირვების API, რომელსაც ბიბლიოთეკა შეუერთდებოდა, ამიტომ მის ტესტებს სჭირდებათ TestCoverageAttribution-ის `.coverageAttribution` თვისება (trait) მათ სუიტაზე. თვისება ვრცელდება მასში ჩადგმულ სუიტებზეც. ტესტები სუიტებში ამ თვისების გარეშე არ იწერენ ტესტის დონის დაფარვას, ამიტომ ისინი გადის მაშინ, როდესაც მათი მიზანი (target) გადის.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **ტესტები არ უნდა ემთხვეოდეს.** Swift Testing ნაგულისხმევად ასრულებს პროცესის ტესტებს პარალელურად, ხოლო დაფარვის მრიცხველებს არ შეუძლიათ განასხვავონ ერთდროულად გაშვებული ტესტები, ამიტომ ეს ტესტები არ იწერენ საკუთარ დაფარვას და ყოველთვის გადის. `.serialized` მხოლოდ ალაგებს სუიტის საკუთარ ტესტებს, ამიტომ ის საკმარისია მხოლოდ მაშინ, როდესაც მიზანს (target) აქვს ერთი სუიტა. XCTest-ს არაფერი სჭირდება: პარალელური ტესტირება ასრულებს თითოეულ ტესტის კლონს საკუთარ პროცესში.
- **გამორთეთ პარალიზაცია თითოეული სატესტო მიზნისთვის.** Xcode აყენებს პარამეტრს თითოეულ სატესტო მიზანზე (test target), ამიტომ შეგიძლიათ გამორთოთ ის მხოლოდ იმ მიზნებისთვის, რომელთა შერჩევაც გსურთ ტესტის მიხედვით, ხოლო სქემის სხვა მიზნები პარალელურად გაგრძელდება. ცალკე სქემა არ არის საჭირო. დააყენეთ ის სატესტო მიზანზე, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, რაც ასევე ასრულებს ამ მიზნის XCTest ტესტებს კლონების გარეშე. Tuist-ის მიერ გენერირებული სქემები იღებენ მას პროექტის `testingOptions`-დან, გამორთულია, თუ არ შეიცავს `.parallelizable` ან `.swiftTestingOnlyParallelizable`-ს. `-parallel-testing-enabled YES` ან `NO`-ის გადაცემა `tuist test`-ზე გადაწერს ყოველი მიზნის პარამეტრს ამ გაშვებისთვის.
- **გამოტოვებას სჭირდება Swift 6.3 (Xcode 26.4) ან უფრო ახალი.** თვისება აუქმებს ტესტებს, რომლებიც Tuist-მა არ შეარჩია და აღნიშნავს მათ როგორც გამოტოვებულს. უფრო ადრეულ ვერსიებში ტესტები მაინც იწერენ დაფარვას, მაგრამ ისინი, რომლებიც Tuist-მა არ შეარჩია, მაინც გადის.

### ტესტები, რომლებიც ყოველთვის გადის {#tests-that-always-run}

დაფარვა ხედავს მხოლოდ იმ კოდს, რომელსაც ტესტი ასრულებს. ტესტი, რომლის რეალური შესავალი მონაცემებია ფიქსტურები, რესურსები, ქსელი ან გარემო, შეიძლება ჩავარდეს დაფარული კოდის შეცვლის გარეშეც. მონიშნეთ ის როგორც არაგამოსატოვებელი (unskippable) და ის გადის მაშინაც, როდესაც Tuist მას არ შეარჩევს:

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

ეს ვრცელდება მხოლოდ იმ სატესტო მიზნებში (test targets), რომლებიც გადის. მიზანი (target), რომლის ჰეშიც უკვე გაიარა, ან რომლის ტესტებიც Tuist-მა არ შეარჩია, მთლიანად გამოიტოვება და არასდროს იწყება, ამიტომ მისი არაგამოსატოვებელი ტესტებიც არ გადის.

იხილეთ [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) ყველა პარამეტრისთვის.


## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git forge-თან ინტეგრაცია აუცილებელია**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, დააკავშირეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">Tuist პროექტი</.localized_link> Git forge-თან: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> ან <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


მას შემდეგ, რაც თქვენი Tuist პროექტი დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), და დაიწყებთ `tuist test`-ის გამოყენებას თქვენი CI სამუშაო ნაკადის ნაწილად, Tuist პირდაპირ გამოაქვეყნებს კომენტარს თქვენს pull/merge request-ებში, რომელიც მოიცავს ინფორმაციას იმის შესახებ, რომელი ტესტები გაშვებულია და რომელი გამოტოვებული: ![GitHub app კომენტარი Tuist Preview ბმულით](/images/guides/features/selective-testing/github-app-comment.png)


## გამოტოვებების გამოკვლევა დაფაზე {#investigating-misses-on-the-dashboard}

როდესაც ადრე კეშირებული სატესტო მიზანი (test target) გამოჩნდება როგორც გამოტოვება (miss), ტესტების გაშვების გვერდზე არსებული **შერჩევითი ტესტირება** ჩანართი საშუალებას გაძლევთ შეისწავლოთ ის შემავალი მონაცემები, რომლებმაც ჰეში წარმოქმნეს. სტრიქონის გაშლა აჩვენებს თითოეული კომპონენტის ქვეჰეშებს — წყაროები, დამოკიდებულებები, გარემოს ცვლადები, პროექტისა და მიზნის პარამეტრები, Info.plist, უფლებები, ჰედერები და ა.შ., რათა ზუსტად განსაზღვროთ ის შემავალი მონაცემი, რომელიც გაშვებებს შორის შეიცვალა.

გამოიყენეთ **Copy as JSON** ღილაკი შერჩევითი ტესტირების ბარათის თავში, რათა გაიტანოთ ყოველი შერჩევითი ტესტირების მიზანი (target) მისი ჰეშითა და ქვეჰეშებით. JSON-ის შედარება ორ გაშვებას შორის არის ყველაზე სწრაფი გზა იმის დასადასტურებლად, თუ რომელი შესავალი მონაცემი შეიცვალა, როდესაც სატესტო მიზნის ჰეში შეიცვალა.
