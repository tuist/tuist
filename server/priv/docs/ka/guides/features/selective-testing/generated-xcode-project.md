---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · შერჩევითი ტესტირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით მხოლოდ ის Xcode-ის და გენერირებული პროექტის ტესტები, რომლებზეც გავლენა იქონია თქვენმა უახლესმა ცვლილებებმა, Tuist Selective Testing-ის გამოყენებით, რათა უწყვეტ ინტეგრაციას (CI) უკუკავშირი წამებში მიიღოთ."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project}

როგორც კი პროექტი იზრდება, ყოველ პუშზე ყველა ტესტის გაშვება აღარ მასშტაბდება. Tuist-ის შერჩევითი ტესტირება აწარმოებს მხოლოდ იმ ტესტებს, რომელთა სამიზნეები შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ, Tuist-ის <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმის</.localized_link> საფუძველზე.

ტესტების შერჩევითად გასაშვებად თქვენს <.localized_link href="/guides/features/projects">გენერირებულ პროექტთან</.localized_link>, გამოიყენეთ `tuist test` ბრძანება. ბრძანება <.localized_link href="/guides/features/projects/hashing">აჰეშავს</.localized_link> თქვენს პროექტს იმავე გზით, როგორც <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშისთვის</.localized_link>, და წარმატების შემთხვევაში ინახავს ჰეშებს, რათა მომავალ გაშვებებში განსაზღვროს, რა შეიცვალა. მომავალ გაშვებებში, `tuist test` გამჭვირვალედ იყენებს ჰეშებს ტესტების ფილტრაციისთვის და აწარმოებს მხოლოდ მათ, რომლებიც შეიცვალა ბოლო წარმატებული ტესტების გაშვების შემდეგ.

`tuist test` პირდაპირ ინტეგრირდება <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშთან</.localized_link>, რათა გამოიყენოს მაქსიმალური რაოდენობის ბინარული ფაილები თქვენი ადგილობრივი ან დისტანციური საცავიდან და შეამციროს ბილდის დრო თქვენი ტესტების სუიტის გაშვებისას. შერჩევითი ტესტირებისა და მოდულის ქეშირების კომბინაციამ შეიძლება მკვეთრად შეამციროს დრო, რომელიც სჭირდება ტესტების გაშვებას თქვენს CI-ზე.

თუ თქვენი ტესტები მხოლოდ სიმულატორის სამიზნეებს ეხება, გადაეცით `--destination simulator`, რათა `tuist test` გამოიყენოს და ჩამოტვირთოს მხოლოდ ქეშირებული ბინარული ფაილების სიმულატორის ნაწილები. იხილეთ <.localized_link href="/guides/features/cache/module-cache#destination-selection">დანიშნულების არჩევა</.localized_link>. შერჩევითი ტესტირების ჰეშები ერთნაირია ყოველი `--destination` მნიშვნელობისთვის.

## ბილდისა და ტესტების ცალკეული ჯობები {#separate-build-and-test-jobs}

შერჩევითი ტესტირება მხარდაჭერილია ბილდისა და ტესტების ცალკეული ჯობებით. გაუშვით `tuist test --build-only` ბილდის ჯობში, რათა Tuist-მა შეინახოს `selective-testing-graph.json` ფაილი ბილდის მიერ გამოცემულ პროდუქტებთან ერთად. ეს გრაფი შეიცავს ჰეშებს, რომლებიც საჭიროა შერჩევითი ტესტირებისთვის, ამიტომ ტესტების ჯობას არ სჭირდება პროექტის ხელახლა გენერირება ან Swift Package დამოკიდებულებების გადაწყვეტა, რათა დაადგინოს, რომელი სამიზნეები უნდა გაეშვას.

Tuist წერს გრაფს ორ ადგილას `--build-only`-ის დროს:

- `.xctestproducts` ბანდლის შიგნით, როდესაც გადასცემთ `-testProductsPath`-ს.
- ყოველი `.xctestrun` ფაილის გვერდით წარმოებული მონაცემების `Build/Products/` დირექტორიაში.

დააქეშეთ ნებისმიერი გამოსავალი აგებულ პროდუქტებთან ერთად და გადაეცით იგივე გზა `--without-building`-ს ტესტების ჯობში. ორივე ფორმა მუშაობს:

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

როდესაც Tuist ვერ პოულობს ამ გრაფს შეყვანის გვერდით (მაგალითად, როდესაც ბილდის ჯობმა გამოიყენა ჩვეულებრივი `xcodebuild build-for-testing` `tuist test --build-only`-ის ნაცვლად), ის გადადის პროექტის ხელახლა გენერირებაზე, რათა მაინც გამოთვალოს დაზარალებული სამიზნეები. ამ ალტერნატიულ გზას სჭირდება Swift Package დამოკიდებულებების გადაწყვეტა ტესტების ჯობზე, ამიტომ ჯერ გაუშვით `tuist install` ან დააქეშეთ `Tuist/.build` ჯობებს შორის.

გრაფი ასახავს წყაროს ხეს ისე, როგორც ის იყო ბილდის დროს. გაუშვით ტესტების ჯობა იმავე კომიტზე, რაზეც ბილდის ჯობა — თუ წყარო განსხვავდება ორს შორის, ჰეშები აღარ ემთხვევა წყაროს და შერჩევითმა ტესტირებამ შეიძლება გამოტოვოს ტესტები, რომლებიც რეალურად ჩავარდებოდა ახალ წყაროზე.

### რომელი ფლაგი უნდა გამოვიყენო? {#which-flag-should-i-use}

`.xctestrun` და `.xctestproducts` არის Xcode-ის ორი განსხვავებული გამოსავალი ფორმატი, და ისინი აწონასწორებენ პორტაბელურობას პაიპლაინის მოხერხებულობასთან:

- **`-testProductsPath` (`.xctestproducts`) — რეკომენდებულია ახალი პაიპლაინებისთვის.** ეს არის თვითკმარი დირექტორია: აგებული `.xctest` ბინარული ფაილები და მათი `.xctestrun` ფაილები ცხოვრობენ მის შიგნით გზებით, რომლებიც შეფარდებულია ბანდლის ფესვთან, ამიტომ ის რჩება ვალიდური, სადაცაც არ უნდა აღმოჩნდეს.
- **`-xctestrun` (ნედლი `.xctestrun`) — გამოიყენეთ, თუ უკვე გაქვთ პაიპლაინი, აგებული წარმოებული მონაცემების გარშემო.** `xcodebuild build-for-testing` წერს `.xctestrun`-ს `<derivedData>/Build/Products/`-ის თავში ნაგულისხმევად და მიმართავს მას ტესტების ბანდლებზე, რომლებიც ცხოვრობენ ამ ხის სხვა ადგილას. მისი ხელახლა გამოყენება სხვა ჯობში ნიშნავს გზების შენარჩუნებას `Build/Products/`-ში უცვლელად.

თუ ახალს იწყებთ, უპირატესობა მიანიჭეთ `-testProductsPath`-ს. თუ Tuist-ს აკავშირებთ არსებულ პაიპლაინთან, რომელიც უკვე აქეშებს წარმოებულ მონაცემებს, `-xctestrun` იღებს იმავე სწრაფ გზას, სანამ ბილდის ჯობა გადის `tuist test --build-only`-ის მეშვეობით.

ნებისმიერი შეყვანის რეჟიმია ურთიერთგამომრიცხავია `-workspace`/`-project`/`-scheme`-თან, ამიტომ Tuist ტოვებს ამ ფლაგებს, როდესაც გადამცემი არგუმენტები შეიცავს `-xctestrun`-ს ან `-testProductsPath`-ს, და გადასცემს შერჩეულ სამიზნეებს `-only-testing`-ის მეშვეობით.

> [!WARNING]
> **მოდულის vs ფაილის დონის გრანულარობა**
>
> კოდში ტესტებსა და წყაროებს შორის დამოკიდებულებების აღმოჩენის შეუძლებლობის გამო, ნაგულისხმევი შერჩევითი ტესტირების მაქსიმალური გრანულარობა არის სამიზნის დონეზე. [დაფარვის სტრატეგია](#coverage-based-test-selection) ამცირებს მას ცალკეულ ტესტებამდე. ამიტომ, ჩვენ გირჩევთ, შეინარჩუნოთ თქვენი სამიზნეები მცირე და ფოკუსირებული, რათა მაქსიმალურად გაზარდოთ შერჩევითი ტესტირების სარგებელი.


## დაფარვაზე დაფუძნებული ტესტების შერჩევა {#coverage-based-test-selection}

> [!NOTE]
> **ადრეული წვდომა**
>
> დაფარვაზე დაფუძნებული ტესტების შერჩევა არის ადრეულ წვდომაში. დაგვიკავშირდით, რათა ჩავრთოთ ის თქვენს ანგარიშზე. სანამ არ ჩაირთვება, სტრატეგია იქცევა როგორც ნაგულისხმევი შერჩევითი ტესტირება.

ნაგულისხმევად, შერჩევითი ტესტირება ტოვებს მთლიან ტესტების სამიზნეებს, რომელთა ჰეში უკვე გაიარა. `.coverage()` სტრატეგია მიდის უფრო შორს: დარჩენილ ტესტების სამიზნეებში, ის ასევე ტოვებს ტესტებს, რომელთა კოდის დაფარვა ადრეულ გაშვებაზე არ მოიცავს არცერთ ფაილს, რომელსაც თქვენმა ცვლილებამ შეეხო. ის მუშაობს XCTest და XCUITest ტესტებთან, და [Swift Testing](#swift-testing) ტესტებთან სუიტებში, რომლებიც მისთვის არის მომზადებული. ჩართეთ ის `Tuist.swift`-ში:

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

- **დაფარვის ატვირთვები.** Tuist ირჩევს ტესტებს იმ დაფარვის მიხედვით, რომელიც ადრეულმა გაშვებებმა ატვირთა, ამიტომ `tuist test` ვერ ტვირთავს მანიფესტს, რომელიც აყენებს `.coverage()`-ს `upload: false`-ით.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 ან უფრო ახალი** [დაკავშირებული თქვენი ტესტების სამიზნეებით](#linking-testcoverageattribution). ის იწერს, თუ რომელ ფაილებს ასრულებს თითოეული ტესტი და ტოვებს ტესტებს, რომლებიც Tuist-მა არ შეარჩია. სამიზნე მის გარეშე მხოლოდ მთლიანად შეიძლება გამოტოვებულ იქნას, როგორც ნაგულისხმევით.
- **სრული ტესტების გაშვებები, საკმარისად ხშირად.** გაშვება `tuist test --no-selective-testing`-ით ასრულებს ყველა ტესტს და ხდება საბაზისო ხაზი. შერჩევითი გაშვება ადარებს ბოლო ერთს მისი კომიტის ისტორიაში იმავე პლატფორმაზე, და არ აყენებს დაფარვას მის გარეშე. სად და რამდენად ხშირად გაუშვათ ისინი, დამოკიდებულია იმაზე, თუ როგორ მუშაობს თქვენი გუნდი, მაგალითად, თქვენი ნაგულისხმევი ბრენჩის ყოველ კომიტზე, ყოველ ღამე, ან რელიზის ბრენჩებზე. ჩვენ გირჩევთ ნაგულისხმევ ბრენჩს: სრული გაშვება იქ ასევე იჭერს, სანამ ცვლილება გაიგზავნება, იმას, რასაც დაფარვა ვერ ხედავს, მაგალითად, ფიქსტურას ან სერვისს, რომელზეც ტესტი არის დამოკიდებული.

სტრატეგიის ჩართვისას, `tuist test` ტოვებს სამიზნეებს, რომელთა ჰეში უკვე გაიარა, შემდეგ კი ეკითხება Tuist-ს, თუ რომელ ტესტებზე დარჩენილი სამიზნეებიდან შეიძლება იმოქმედოს თქვენმა ცვლილებამ. სამიზნეები, რომლებსაც არ აქვთ დაზარალებული ტესტი, არ აგებენ. ახალი ტესტები, ტესტები, რომლებიც ბოლოჯერ ჩავარდა, ტესტები შეცვლილ ტესტის ფაილში და ტესტები ჩაწერილი დაფარვის გარეშე ყოველთვის გადის.

ზოგჯერ დაფარვა არ გამოიყენება და გამომავალი მონაცემები ხსნიან რატომ: ყველა ტესტი იმ სამიზნეებისთვის, რომელთა ჰეში არ გაიარა, სრულდება, როგორც ნაგულისხმევი შერჩევითი ტესტირების შემთხვევაში. ეს ხდება მაშინ, როდესაც არ არსებობს ბოლო დროის საბაზისო ხაზი იმავე პლატფორმაზე, როდესაც ცვლილება ეხება 5,000-ზე მეტ ფაილს, ან როდესაც შეიცვალა ფაილი, რომელსაც შეუძლია ნებისმიერი ტესტის გავლენა, მაგალითად `Package.resolved`, `Project.swift` ან `.xcconfig`. ყველა ტესტის გასაშვებად, გადაეცით `--no-selective-testing`.

> [!NOTE]
> **ტესტების დაფარვა**
>
> დაფარვის ინსტრუმენტები, რომლებიც კითხულობენ ერთი გაშვების ანგარიშს, Xcode-ის ჩათვლით, ვარაუდობენ, რომ მთელი ტესტების ნაკრები შესრულდა, ამიტომ შერჩევითი გაშვების ანგარიში ტოვებს გამოტოვებულ ტესტებს. Tuist-ის <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">კოდის დაფარვა</.localized_link> გადააქვს გამოტოვებული ტესტის სამიზნეების დაფარვა წინა გაშვებიდან, იყენებს <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">სამიზნის დონის დაფარვას</.localized_link>, რომელსაც ის იწერს ყოველ გაშვებაზე.

### TestCoverageAttribution-ის მიბმა {#linking-testcoverageattribution}

დაამატეთ პაკეტი `Tuist/Package.swift`-ში, მიბმული მის მინორულ ვერსიაზე, რადგან 0.x მინორული რელიზი შეიძლება შეცვალოს იმის ჩაწერა:

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

შემდეგ დაამატეთ ის თქვენს ტესტის სამიზნეებში და არასდროს აპლიკაციის სამიზნეში:

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

Tuist ნაგულისხმევად აკავშირებს პაკეტებს როგორც სტატიკურ ჩარჩოებს. XCTest-ის მხოლოდ სამიზნე არაფერს უკავშირდება პაკეტში, ამიტომ ლინკერი აგდებს მას, და მასთან ერთად ჩაწერას და გამოტოვებას. ან დაამატეთ `-ObjC` ტესტის სამიზნის `OTHER_LDFLAGS`-ში, ან დააკავშირეთ პაკეტი დინამიურად `Tuist/Package.swift`-ში:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing-ს არ აქვს დაკვირვების API, რომელსაც ბიბლიოთეკა შეუერთდება, ამიტომ მის ტესტებს სჭირდებათ TestCoverageAttribution-ის `.coverageAttribution` თვისება მათ ნაკრებზე. თვისება ვრცელდება ნაკრებებზე, რომლებიც ჩადგმულია იმაში, რომელსაც აქვს ის. ტესტები ნაკრებებში მის გარეშე არ იწერენ ტესტის დონის დაფარვას, ამიტომ ისინი სრულდება ყოველთვის, როდესაც მათი სამიზნე სრულდება.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **ტესტები არ უნდა ემთხვეოდეს.** Swift Testing ნაგულისხმევად ასრულებს პროცესის ტესტებს პარალელურად, და დაფარვის მრიცხველებს არ შეუძლიათ განასხვავონ ტესტები, რომლებიც ერთდროულად სრულდება, ამიტომ ეს ტესტები არ იწერენ საკუთარ დაფარვას და ყოველთვის სრულდება. `.serialized` მხოლოდ ალაგებს ნაკრების საკუთარ ტესტებს, ამიტომ ის საკმარისია მხოლოდ მაშინ, როდესაც სამიზნეს აქვს ერთი ნაკრები. XCTest-ს არაფერი სჭირდება: პარალელური ტესტირება ასრულებს თითოეულ ტესტის კლონს საკუთარ პროცესში.
- **გამორთეთ პარალელიზაცია თითოეული ტესტის სამიზნისთვის.** Xcode აყენებს პარამეტრს თითოეულ ტესტის სამიზნეზე, ამიტომ შეგიძლიათ გამორთოთ ის მხოლოდ იმ სამიზნეებისთვის, რომლებისთვისაც გსურთ ტესტის შერჩევა, და სქემის სხვა სამიზნეები განაგრძობენ პარალელურად მუშაობას. ცალკე სქემა არ არის საჭირო. დააყენეთ ის შესატესტავ სამიზნეზე, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, რომელიც ასევე ასრულებს იმ სამიზნის XCTest ტესტებს კლონების გარეშე. Tuist-ის მიერ გენერირებული სქემები იღებენ მას პროექტის `testingOptions`-დან, გამორთულია, თუ არ შეიცავს `.parallelizable` ან `.swiftTestingOnlyParallelizable`. `-parallel-testing-enabled YES` ან `NO`-ის გადაცემა `tuist test`-ისთვის ანაცვლებს თითოეული სამიზნის პარამეტრს იმ გაშვებისთვის.
- **გამოტოვებას სჭირდება Swift 6.3 (Xcode 26.4) ან უფრო ახალი.** თვისება აუქმებს ტესტებს, რომლებიც Tuist-მა არ შეარჩია და ანგარიშგებაში აჩვენებს მათ როგორც გამოტოვებულს. უფრო ადრეულ ვერსიებში, ტესტები მაინც იწერენ დაფარვას, მაგრამ ისინი, რომლებიც Tuist-მა არ შეარჩია, მაინც სრულდება.

### ტესტები, რომლებიც ყოველთვის სრულდება {#tests-that-always-run}

დაფარვა ხედავს მხოლოდ იმ კოდს, რომელსაც ტესტი ასრულებს. ტესტი, რომლის რეალური შემავალი მონაცემებია ფიქსტურები, რესურსები, ქსელი ან გარემო, შეიძლება ჩავარდეს ნებისმიერი დაფარული კოდის შეცვლის გარეშე. მონიშნეთ ის როგორც არაგამოსატოვებელი და ის შესრულდება მაშინაც, როდესაც Tuist მას არ შეარჩევს:

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

ეს მოქმედებს მხოლოდ იმ ტესტის სამიზნეებში, რომლებიც სრულდება. სამიზნე, რომლის ჰეში უკვე გაიარა, ან რომლის ტესტებიდანაც Tuist-მა არცერთი არ შეარჩია, მთლიანად გამოიტოვება და არასდროს იწყება, ამიტომ მისი არაგამოსატოვებელი ტესტებიც არ სრულდება.

იხილეთ [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) ყველა პარამეტრისთვის.

### შერჩევის ინსპექტირება {#inspecting-a-selection}

ტესტის გაშვების შერჩევითი ტესტირების ჩანართი აჩვენებს, თუ რა შეარჩია დაფარვამ და რატომ. იგივე მონაცემები ხელმისაწვდომია CLI-დან, `--json`-ით სკრიპტინგისთვის, და აგენტებისთვის <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol სერვერის</.localized_link> მეშვეობით:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

როდესაც დაფარვა არ გამოიყენება, ტესტები მაინც ითვლება როგორც დაფარვაზე დაფუძნებული შერჩევა: მათი მიზეზი ხსნის, რატომ ვერ გადაწყვიტა დაფარვამ, მაგალითად `tracked_file_changed`.


## Pull/merge მოთხოვნის კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git forge ინტეგრაცია საჭიროა**
>
> ავტომატური pull/merge მოთხოვნის კომენტარების მისაღებად, დააკავშირეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">Tuist პროექტი</.localized_link> Git forge-თან: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>, ან <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


მას შემდეგ, რაც თქვენი Tuist პროექტი დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), და დაიწყებთ `tuist test`-ის გამოყენებას თქვენი CI სამუშაო ნაკადის ნაწილად, Tuist გამოაქვეყნებს კომენტარს პირდაპირ თქვენს pull/merge მოთხოვნებში, მათ შორის იმას, თუ რომელი ტესტები შესრულდა და რომელი გამოიტოვა: ![GitHub აპის კომენტარი Tuist Preview ბმულით](/images/guides/features/selective-testing/github-app-comment.png)


## გამოტოვებების კვლევა დაფაზე {#investigating-misses-on-the-dashboard}

როდესაც ადრე კეშირებული ტესტის სამიზნე ჩანს როგორც გამოტოვება, ტესტის გაშვების გვერდზე **შერჩევითი ტესტირების** ჩანართი საშუალებას გაძლევთ ჩაუღრმავდეთ იმ შემავალ მონაცემებს, რომლებმაც წარმოქმნეს ჰეში. რიგის გაფართოება აჩვენებს კომპონენტების ქვეჰეშებს — წყაროებს, დამოკიდებულებებს, გარემოს ცვლადებს, პროექტის და სამიზნის პარამეტრებს, Info.plist-ს, უფლებებს, სათაურებს და ა.შ. — რათა ზუსტად განსაზღვროთ შემავალი მონაცემი, რომელიც შეიცვალა გაშვებებს შორის.

გამოიყენეთ **Copy as JSON** ღილაკი შერჩევითი ტესტირების ბარათის თავში, რათა გაიტანოთ ყველა შერჩევითი ტესტირების სამიზნე მისი ჰეშით და ქვეჰეშებით. JSON-ის შედარება ორ გაშვებას შორის არის ყველაზე სწრაფი გზა იმის დასადასტურებლად, თუ რომელი შემავალი მონაცემი შეიცვალა, როდესაც ტესტის სამიზნის ჰეში შეიცვალა.
