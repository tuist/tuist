---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · შერჩევითი ტესტირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეასრულეთ მხოლოდ ის Xcode-ისა და გენერირებული პროექტის ტესტები, რომლებზეც თქვენი ბოლო ცვლილებები აისახა, Tuist Selective Testing-ის მეშვეობით, რათა უწყვეტმა ინტეგრაციამ უკუკავშირი წამებში მოგაწოდოთ."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project}

როგორც კი პროექტი იზრდება, ყოველ push-ზე ყველა ტესტის გაშვება ვეღარ მასშტაბირდება. Tuist-ის შერჩევითი ტესტირება აწარმოებს მხოლოდ იმ ტესტებს, რომელთა target-ები შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ, Tuist-ის <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმის</.localized_link> საფუძველზე.

შერჩევითად ტესტების გასაშვებად თქვენს <.localized_link href="/guides/features/projects">გენერირებულ პროექტთან</.localized_link>, გამოიყენეთ `tuist test` ბრძანება. ბრძანება <.localized_link href="/guides/features/projects/hashing">აჰეშავს</.localized_link> თქვენს პროექტს ისევე, როგორც <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშისთვის</.localized_link>, და წარმატების შემთხვევაში ინახავს ჰეშებს, რათა მომავალ გაშვებებში განსაზღვროს, რა შეიცვალა. მომავალ გაშვებებში, `tuist test` გამჭვირვალედ იყენებს ჰეშებს ტესტების ფილტრაციისთვის და აწარმოებს მხოლოდ მათ, რომლებიც შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ.

`tuist test` პირდაპირ ინტეგრირდება <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშთან</.localized_link>, რათა გამოიყენოს მაქსიმალურად ბინარები თქვენი ადგილობრივი ან დისტანციური საცავიდან და გააუმჯობესოს აგების დრო თქვენი ტესტების ნაკრების გაშვებისას. შერჩევითი ტესტირებისა და მოდულის ქეშირების კომბინაციამ შეიძლება მნიშვნელოვნად შეამციროს დრო, რომელიც სჭირდება ტესტების გაშვებას თქვენს CI-ზე.

თუ თქვენი ტესტების გაშვება მიზნად ისახავს მხოლოდ სიმულატორებს, გადაეცით `--destination simulator`, რათა `tuist test` გამოიყენოს და ჩამოტვირთოს მხოლოდ ქეშირებული ბინარების სიმულატორის სლაისები. იხილეთ <.localized_link href="/guides/features/cache/module-cache#destination-selection">დანიშნულების არჩევა</.localized_link>. შერჩევითი ტესტირების ჰეშები იგივეა ნებისმიერი `--destination` მნიშვნელობისთვის.

## აგებისა და ტესტირების ცალკეული სამუშაოები {#separate-build-and-test-jobs}

შერჩევითი ტესტირება უჭერს მხარს აგებისა და ტესტირების ცალკეულ სამუშაოებს. გაუშვით `tuist test --build-only` აგების სამუშაოში, რათა Tuist-მა შეინახოს `selective-testing-graph.json` ფაილი აგების შედეგად გამოშვებული პროდუქტების გვერდით. ეს გრაფი შეიცავს ჰეშებს, რომლებიც საჭიროა შერჩევითი ტესტირებისთვის, ამიტომ ტესტირების სამუშაოს არ სჭირდება პროექტის ხელახლა გენერირება ან Swift Package დამოკიდებულებების ამოხსნა იმის დასადგენად, თუ რომელი target-ები უნდა გაეშვას.

Tuist წერს გრაფს ორ ადგილას `--build-only`-ის დროს:

- `.xctestproducts` ბანდლის შიგნით, როდესაც გადასცემთ `-testProductsPath`-ს.
- ყოველი `.xctestrun` ფაილის გვერდით derived data-ს `Build/Products/` დირექტორიაში.

შეინახეთ ნებისმიერი გამონატანი აგებული პროდუქტების გვერდით და გადაეცით იგივე გზა `--without-building`-ს ტესტირების სამუშაოში. ორივე ფორმა მუშაობს:

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

როდესაც Tuist ვერ პოულობს ამ გრაფს შეყვანის გვერდით (მაგალითად, როდესაც აგების სამუშაო იყენებდა ჩვეულებრივ `xcodebuild build-for-testing`-ს `tuist test --build-only`-ის ნაცვლად), ის ბრუნდება პროექტის ხელახლა გენერირებაზე, რათა მაინც გამოთვალოს დაზარალებული target-ები. ამ ალტერნატიულ ვარიანტს სჭირდება Swift Package დამოკიდებულებების ამოხსნა ტესტირების სამუშაოზე, ამიტომ ჯერ გაუშვით `tuist install` ან შეინახეთ `Tuist/.build` სამუშაოებს შორის.

გრაფი ასახავს წყაროს ხეს ისე, როგორიც ის იყო აგების დროს. გაუშვით ტესტირების სამუშაო იმავე commit-ზე, რაზეც აგების სამუშაო — თუ წყარო იცვლება მათ შორის, ჰეშები აღარ ემთხვევა წყაროს და შერჩევითმა ტესტირებამ შეიძლება გამოტოვოს ტესტები, რომლებიც რეალურად ჩავარდებოდა უფრო ახალ წყაროსთან.

### რომელი ფლაგი უნდა გამოვიყენო? {#which-flag-should-i-use}

`.xctestrun` და `.xctestproducts` არის Xcode-ის ორი განსხვავებული გამონატანის ფორმატი და ისინი წონაში აყენებენ პორტაბელურობას pipeline-ის მოხერხებულობის წინააღმდეგ:

- **`-testProductsPath` (`.xctestproducts`) — რეკომენდებულია ახალი pipeline-ებისთვის.** ეს არის თვითკმარი დირექტორია: აგებული `.xctest` ბინარები და მათი `.xctestrun` ფაილები ცხოვრობენ მის შიგნით ისე, რომ გზები შეფარდებულია ბანდლის ფესვთან, ამიტომ ის ძალაში რჩება ნებისმიერ ადგილას, სადაცაც არ უნდა აღმოჩნდეს.
- **`-xctestrun` (ნედლი `.xctestrun`) — გამოიყენეთ, თუ უკვე გაქვთ pipeline აწყობილი derived data-ს გარშემო.** `xcodebuild build-for-testing` წერს `.xctestrun`-ს `<derivedData>/Build/Products/`-ის თავში ნაგულისხმევად და მიუთითებს ტესტ ბანდლებზე, რომლებიც ცხოვრობენ ამ ხის სხვა ადგილას. მისი ხელახლა გამოყენება სხვა სამუშაოში ნიშნავს გზების შენარჩუნებას `Build/Products/`-ში უცვლელად.

თუ ახალს იწყებთ, უპირატესობა მიანიჭეთ `-testProductsPath`-ს. თუ Tuist-ს აერთებთ არსებულ pipeline-ში, რომელიც უკვე ინახავს derived data-ს ქეშში, `-xctestrun` იღებს იმავე სწრაფ გზას, სანამ აგების სამუშაო გადის `tuist test --build-only`-ით.

ნებისმიერი შეყვანის რეჟიმი ურთიერთგამომრიცხავია `-workspace`/`-project`/`-scheme`-თან, ამიტომ Tuist ტოვებს ამ ფლაგებს, როდესაც passthrough არგუმენტები შეიცავს `-xctestrun`-ს ან `-testProductsPath`-ს, და გადასცემს შერჩეულ target-ებს `-only-testing`-ით.

> [!WARNING]
> **მოდულის vs ფაილის დონის გრანულარობა**
>
> კოდში ტესტებსა და წყაროებს შორის დამოკიდებულებების აღმოჩენის შეუძლებლობის გამო, ნაგულისხმევი შერჩევითი ტესტირების მაქსიმალური გრანულარობა არის target-ის დონეზე. [დაფარვის სტრატეგია](#coverage-based-test-selection) ამცირებს მას ცალკეულ ტესტებამდე. ამიტომ, ჩვენ გირჩევთ, თქვენი target-ები იყოს მცირე და ფოკუსირებული, რათა მაქსიმალურად გამოიყენოთ შერჩევითი ტესტირების უპირატესობები.


## დაფარვაზე დაფუძნებული ტესტების შერჩევა {#coverage-based-test-selection}

> [!NOTE]
> **ადრეული წვდომა**
>
> დაფარვაზე დაფუძნებული ტესტების შერჩევა არის ადრეულ წვდომაში. დაგვიკავშირდით, რათა ჩავრთოთ ის თქვენს ანგარიშზე. სანამ ის ჩართული არ იქნება, სტრატეგია იქცევა როგორც ნაგულისხმევი შერჩევითი ტესტირება.

ნაგულისხმევად, შერჩევითი ტესტირება ტოვებს მთლიან ტესტ target-ებს, რომელთა ჰეში უკვე გაიარა. `.coverage()` სტრატეგია მიდის უფრო შორს: დარჩენილ ტესტ target-ებში, ის ასევე ტოვებს იმ ტესტებს, რომელთა კოდის დაფარვა წინა გაშვებაზე არ მოიცავდა არცერთ ფაილს, რომელსაც თქვენმა ცვლილებამ შეეხო. ის მუშაობს XCTest და XCUITest ტესტებთან, და [Swift Testing](#swift-testing) ტესტებთან suite-ებში, რომლებიც მისთვის არის მომზადებული. ჩართეთ ის `Tuist.swift`-ში:

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

- **დაფარვის ატვირთვები.** Tuist ირჩევს ტესტებს იმ დაფარვის მიხედვით, რომელიც წინა გაშვებებმა ატვირთეს, ამიტომ `tuist test` ვერ ტვირთავს მანიფესტს, რომელიც აყენებს `.coverage()`-ს `upload: false`-ით.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 ან უფრო ახალი** [დაკავშირებული თქვენი ტესტ target-ებით](#linking-testcoverageattribution). ის იწერს, თუ რომელ ფაილებს ასრულებს თითოეული ტესტი და ტოვებს იმ ტესტებს, რომლებიც Tuist-მა არ შეარჩია. target მის გარეშე ყოველთვის ტოვდება მთლიანად, როგორც ნაგულისხმევ შემთხვევაში.
- **სრული ტესტების გაშვება, საკმარისად ხშირად.** გაშვება `tuist test --no-selective-testing`-ით ასრულებს ყველა ტესტს და ხდება საბაზისო ხაზი. შერჩევითი გაშვება ადარებს ბოლო ერთს მისი commit-ის ისტორიაში იმავე პლატფორმაზე და არ იყენებს დაფარვას მის გარეშე. სად და რამდენად ხშირად უნდა გაუშვათ ისინი, დამოკიდებულია თქვენი გუნდის მუშაობის წესზე, მაგალითად, თქვენი ნაგულისხმევი branch-ის ყოველ commit-ზე, ყოველ ღამე, ან release branch-ებზე. ჩვენ გირჩევთ ნაგულისხმევ branch-ს: სრული გაშვება იქ ასევე იჭერს, სანამ ცვლილება გაიგზავნება, იმას, რასაც დაფარვა ვერ ხედავს, მაგალითად fixture-ს ან სერვისს, რომელზეც ტესტი არის დამოკიდებული.

სტრატეგიის ჩართვისას, `tuist test` ტოვებს target-ებს, რომელთა ჰეში უკვე გაიარა, შემდეგ კი ეკითხება Tuist-ს, თუ რომელ ტესტებს შეუძლია თქვენმა ცვლილებამ შეეხოს დარჩენილ target-ებში. target-ები, რომლებსაც არ აქვთ დაზარალებული ტესტი, არ აგებენ. ახალი ტესტები, ტესტები, რომლებიც ბოლოჯერ ჩავარდა, ტესტები შეცვლილ ტესტ ფაილში და ტესტები ჩაწერილი დაფარვის გარეშე ყოველთვის გაეშვება.

ზოგჯერ დაფარვა არ გამოიყენება და შედეგი ხსნის რატომ: ყველა იმ target-ის ტესტი, რომლის ჰეში არ გაიარა, ეშვება, როგორც ნაგულისხმევი შერჩევითი ტესტირების დროს. ეს ხდება მაშინ, როდესაც არ არსებობს ბოლო საბაზისო ხაზი იმავე პლატფორმაზე, როდესაც ცვლილება ეხება 5,000-ზე მეტ ფაილს, ან როდესაც შეიცვალა ფაილი, რომელსაც შეუძლია ნებისმიერი ტესტის გავლენა, მაგალითად `Package.resolved`, `Project.swift`, ან `.xcconfig`. ყველა ტესტის გასაშვებად, გადაეცით `--no-selective-testing`.

> [!NOTE]
> **ტესტის დაფარვა**
>
> დაფარვის ინსტრუმენტები, რომლებიც კითხულობენ ერთი გაშვების ანგარიშს, Xcode-ის ჩათვლით, ვარაუდობენ, რომ მთელი ტესტების სუიტა გაეშვა, ამიტომ შერჩევითი გაშვების ანგარიში ტოვებს გამოტოვებულ ტესტებს. Tuist-ის <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">კოდის დაფარვა</.localized_link> კი გადააქვს გამოტოვებული სატესტო target-ების დაფარვა წინა გაშვებიდან, იყენებს <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">target-ის დონის დაფარვას</.localized_link>, რომელსაც ის ყოველ გაშვებაზე იწერს.

### TestCoverageAttribution-ის მიბმა {#linking-testcoverageattribution}

დაამატეთ პაკეტი `Tuist/Package.swift`-ში, მიბმული მის უმცირეს ვერსიაზე, რადგან 0.x უმცირესმა გამოშვებამ შეიძლება შეცვალოს ის, რასაც ის იწერს:

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

შემდეგ დაამატეთ ის თქვენს სატესტო target-ებში და არასდროს app target-ში:

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

Tuist ნაგულისხმევად აბამს პაკეტებს სტატიკურ framework-ებად. XCTest-ის მხოლოდ target არაფერს მიმართავს პაკეტიდან, ამიტომ linker ტოვებს მას, და მასთან ერთად ჩაწერასა და გამოტოვებას. ან დაამატეთ `-ObjC` სატესტო target-ის `OTHER_LDFLAGS`-ში, ან დააბამეთ პაკეტი დინამიურად `Tuist/Package.swift`-ში:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing-ს არ აქვს დაკვირვების API, რომელსაც ბიბლიოთეკა შეუერთდებოდა, ამიტომ მის ტესტებს სჭირდება TestCoverageAttribution-ის `.coverageAttribution` თვისება მათ სუიტაზე. თვისება ვრცელდება იმ სუიტებზე, რომლებიც ჩადგმულია იმაში, რომელსაც აქვს ის. ტესტები სუიტებში მის გარეშე არ იწერენ ტესტის დონის დაფარვას, ამიტომ ისინი ეშვებიან ყოველთვის, როდესაც მათი target ეშვება.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **ტესტები არ უნდა გადაიფაროს.** Swift Testing ნაგულისხმევად ასრულებს პროცესის ტესტებს პარალელურად, და დაფარვის მრიცხველებს არ შეუძლიათ განასხვავონ ერთდროულად მომუშავე ტესტები, ამიტომ ეს ტესტები არ იწერენ საკუთარ დაფარვას და ყოველთვის ეშვებიან. `.serialized` მხოლოდ ალაგებს სუიტის საკუთარ ტესტებს, ამიტომ ის საკმარისია მხოლოდ მაშინ, როდესაც target-ს აქვს ერთი სუიტა. XCTest-ს არაფერი სჭირდება: პარალელური ტესტირება ასრულებს თითოეულ ტესტის ასლს საკუთარ პროცესში.
- **გამორთეთ პარალელიზაცია თითოეული სატესტო target-ისთვის.** Xcode აყენებს პარამეტრს თითოეულ სატესტო target-ზე, ამიტომ შეგიძლიათ გამორთოთ ის მხოლოდ იმ target-ებისთვის, რომლებიც გსურთ ტესტის მიხედვით შერჩეული იყოს, და scheme-ის სხვა target-ები განაგრძობენ პარალელურად მუშაობას. ცალკე scheme არ არის საჭირო. დააყენეთ ის testable target-ზე, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, რომელიც ასევე ასრულებს იმ target-ის XCTest ტესტებს ასლების გარეშე. Tuist-ის მიერ გენერირებული schemes იღებენ მას პროექტის `testingOptions`-დან, გამორთულია, თუ არ შეიცავს `.parallelizable` ან `.swiftTestingOnlyParallelizable`. `-parallel-testing-enabled YES` ან `NO`-ის გადაცემა `tuist test`-ისთვის გადაწერს ყველა target-ის პარამეტრს იმ გაშვებისთვის.
- **გამოტოვებას სჭირდება Swift 6.3 (Xcode 26.4) ან უფრო ახალი.** თვისება აუქმებს ტესტებს, რომლებიც Tuist-მა არ შეარჩია და აღწერს მათ როგორც გამოტოვებულს. უფრო ადრეული ვერსიებით, ტესტები მაინც იწერენ დაფარვას, მაგრამ ისინი, რომლებიც Tuist-მა არ შეარჩია, მაინც ეშვებიან.

### ტესტები, რომლებიც ყოველთვის ეშვებიან {#tests-that-always-run}

დაფარვა ხედავს მხოლოდ კოდს, რომელსაც ტესტი ასრულებს. ტესტი, რომლის რეალური შემავალი მონაცემებია fixture-ები, რესურსები, ქსელი ან გარემო, შეიძლება გაფუჭდეს ნებისმიერი დაფარული კოდის შეცვლის გარეშე. მონიშნეთ ის როგორც არაგამოტოვებადი და ის ეშვება მაშინაც, როდესაც Tuist მას არ შეარჩევს:

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

ეს მოქმედებს მხოლოდ იმ სატესტო target-ებში, რომლებიც ეშვებიან. target, რომლის ჰეში უკვე გაიარა, ან რომლის არცერთი ტესტი Tuist-მა არ შეარჩია, მთლიანად გამოტოვებულია და არასდროს იწყება, ამიტომ მისი არაგამოტოვებადი ტესტებიც არ ეშვებიან.

იხილეთ [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) ყველა ვარიანტისთვის.

### შერჩევის ინსპექტირება {#inspecting-a-selection}

ტესტების გაშვების Sherecheviti Testireba tab აჩვენებს, რა შეარჩია დაფარვამ და რატომ. იგივე მონაცემები ხელმისაწვდომია CLI-დან, `--json`-ით სკრიპტინგისთვის, და აგენტებისთვის <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>-ის მეშვეობით:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

როდესაც დაფარვა არ გამოიყენება, ტესტები მაინც ითვლება როგორც დაფარვაზე დაფუძნებული შერჩევა: მათი მიზეზი ხსნის, რატომ ვერ გადაწყვიტა დაფარვამ, მაგალითად `tracked_file_changed`.


## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git forge ინტეგრაცია საჭიროა**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, დააინტეგრეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">Tuist project</.localized_link> Git forge-თან: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>, ან <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


მას შემდეგ, რაც თქვენი Tuist project დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), და დაიწყებთ `tuist test`-ის გამოყენებას თქვენი CI workflow-ის ნაწილად, Tuist გამოაქვეყნებს კომენტარს პირდაპირ თქვენს pull/merge requests-ში, მითითებით, რომელი ტესტები გაეშვა და რომელი გამოტოვდა: ![GitHub app კომენტარი Tuist Preview ბმულით](/images/guides/features/selective-testing/github-app-comment.png)


## გამოტოვებების შესწავლა dashboard-ზე {#investigating-misses-on-the-dashboard}

როდესაც ადრე cached სატესტო target ჩანს როგორც გამოტოვება, **Selective Testing** tab ტესტების გაშვების გვერდზე საშუალებას გაძლევთ ჩაუღრმავდეთ იმ შემავალ მონაცემებს, რომლებმაც წარმოქმნეს ჰეში. რიგის გაფართოება აჩვენებს კომპონენტების subhashes — წყაროები, დამოკიდებულებები, გარემოს ცვლადები, პროექტისა და target-ის პარამეტრები, Info.plist, entitlements, headers და ა.შ. — რათა ზუსტად განსაზღვროთ შემავალი მონაცემი, რომელიც შეიცვალა გაშვებებს შორის.

გამოიყენეთ **Copy as JSON** ღილაკი Selective Testing ბარათის ზედა ნაწილში, რათა გაიტანოთ ყველა შერჩევითი ტესტირების target მისი ჰეშითა და subhashes-ით. JSON-ის შედარება ორ გაშვებას შორის არის ყველაზე სწრაფი გზა იმის დასადასტურებლად, თუ რომელი შემავალი მონაცემი შეიცვალა, როდესაც სატესტო target-ის ჰეში შეიცვალა.
