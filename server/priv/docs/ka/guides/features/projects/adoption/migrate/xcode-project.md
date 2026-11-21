---
{
  "title": "Xcode-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადავიტანოთ Xcode-ის პროექტი Tuist-ზე."
}
---
# Xcode-პროექტის მიგრაცია {#migrate-an-xcode-project}

თუ არ <.localized_link href="/guides/features/projects/adoption/new-project">შექმნით ახალ პროექტს Tuist-ის გამოყენებით</.localized_link>, რა შემთხვევაშიც ყველაფერი ავტომატურად კონფიგურირდება, Xcode-პროექტები Tuist-ის პრიმიტივებით უნდა განსაზღვროთ. ამ პროცესის სირთულე დამოკიდებულია თქვენი პროექტების სირთულეზე.

როგორც ალბათ იცით, Xcode-პროექტები დროთა განმავლობაში შეიძლება გახდეს არაორგანიზებული და რთული: ჯგუფები, რომლებიც არ ემთხვევა დირექტორიების სტრუქტურას, ფაილები, რომლებიც საერთოა რამდენიმე target-ისთვის, ან ფაილის მითითებები, რომლებიც არარსებულ ფაილებზე მიუთითებენ (რამდენიმე მაგალითი). ეს დაგროვილი სირთულე ართულებს ისეთი ბრძანების შექმნას, რომელიც პროექტს საიმედოდ გადაიტანს.

გარდა ამისა, ხელით მიგრაცია შესანიშნავი შესაძლებლობაა თქვენი პროექტების გასაწმენდად და გასამარტივებლად. ამას არა მხოლოდ თქვენი პროექტის დეველოპერები შეაფასებენ, არამედ Xcode-იც, რომელიც მათ დამუშავებასა და ინდექსაციას უფრო სწრაფად შეასრულებს. Tuist-ის სრულად დანერგვის შემდეგ ის უზრუნველყოფს, რომ პროექტები თანმიმდევრულად იყოს განსაზღვრული და მარტივი დარჩეს.

ამ სამუშაოს გასამარტივებლად, გთავაზობთ რამდენიმე სახელმძღვანელოს, რომელიც მომხმარებლებისგან მიღებული უკუკავშირის საფუძველზეა შედგენილი.

## პროექტის სკელეტის შექმნა {#create-project-scaffold}

ჯერ შექმენით თქვენი პროექტის ჩარჩო შემდეგი Tuist-ფაილებით:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` არის manifest-ფაილი, სადაც განსაზღვრავთ თქვენს პროექტს, ხოლო `Package.swift` არის manifest-ფაილი, სადაც განსაზღვრავთ თქვენს დამოკიდებულებებს. `Tuist.swift` ფაილში შეგიძლიათ განსაზღვროთ პროექტის დონის Tuist-პარამეტრები.

> [!TIP]
> **პროექტის სახელი -Tuist სუფიქსით**
>
> არსებულ Xcode-პროექტთან კონფლიქტების თავიდან ასაცილებლად, გირჩევთ პროექტის სახელს დაამატოთ `-Tuist` სუფიქსი. მისი მოცილება შეგიძლიათ პროექტის Tuist-ზე სრულად გადატანის შემდეგ.


## Tuist-პროექტის აგება და ტესტირება CI-ში {#build-and-test-the-tuist-project-in-ci}

იმის უზრუნველსაყოფად, რომ თითოეული ცვლილების მიგრაცია ვალიდურია, გირჩევთ გააფართოვოთ თქვენი უწყვეტი ინტეგრაცია (CI) და ააწყოთ და შეამოწმოთ Tuist-ის მიერ თქვენი manifest-ფაილიდან გენერირებული პროექტი:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## პროექტის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-project-build-settings-into-xcconfig-files}

ამოიღეთ აწყობის პარამეტრები პროექტიდან `.xcconfig` ფაილში, რათა პროექტი უფრო მსუბუქი და ადვილად გადასატანი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტიდან აწყობის პარამეტრების `.xcconfig` ფაილში ამოსაღებად:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

შემდეგ განაახლეთ თქვენი `Project.swift` ფაილი, რათა მიუთითოს ახლად შექმნილ `.xcconfig` ფაილზე:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

შემდეგ გააფართოვეთ თქვენი უწყვეტი ინტეგრაციის პაიპლაინი, რათა შეასრულოს შემდეგი ბრძანება და უზრუნველყოს, რომ აწყობის პარამეტრებში ცვლილებები პირდაპირ `.xcconfig` ფაილებში ხდება:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## პაკეტის დამოკიდებულებების ამოღება {#extract-package-dependencies}

ამოიღეთ თქვენი პროექტის ყველა დამოკიდებულება `Tuist/Package.swift` ფაილში:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

> [!TIP]
> **პროდუქტის ტიპები**
>
> კონკრეტული პაკეტის პროდუქტის ტიპის გადაფარვა შეგიძლიათ მისი `productTypes` ლექსიკონში დამატებით `PackageSettings` სტრუქტურაში. ნაგულისხმევად, Tuist ვარაუდობს, რომ ყველა პაკეტი სტატიკური ფრეიმვორკია.


## მიგრაციის თანმიმდევრობის განსაზღვრა {#determine-the-migration-order}

გირჩევთ target-ების მიგრაცია იმის მიხედვით წარმართოთ, თუ რომელია ყველაზე მეტად დამოკიდებული, რომელი კი — ნაკლებად. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის target-ების ჩამოსათვლელად, დალაგებული დამოკიდებულებების რაოდენობის მიხედვით:

```bash
tuist migration list-targets -p Project.xcodeproj
```

დაიწყეთ target-ების მიგრაცია სიის თავიდან, რადგან ისინი არიან ისინი, ვინზეც ყველაზე მეტად არიან დამოკიდებულნი.


## მიგრაცია სამიზნეების {#migrate-targets}

გადაიტანეთ target-ები ერთ-ერთად. გირჩევთ თითოეული target-ისთვის pull request შექმნათ, რათა ცვლილებები შერწყმამდე განიხილონ და შეამოწმონ.

### ამოიღეთ სამიზნის აგების პარამეტრები `.xcconfig` ფაილებში {#extract-the-target-build-settings-into-xcconfig-files}

როგორც პროექტის აწყობის პარამეტრების შემთხვევაში, ამოიღეთ target-ის აწყობის პარამეტრები `.xcconfig` ფაილში, რათა target უფრო მსუბუქი და ადვილად გადასატანი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება target-იდან აწყობის პარამეტრების `.xcconfig` ფაილში ამოსაღებად:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### განსაზღვრეთ სამიზნე `Project.swift` ფაილში {#define-the-target-in-the-projectswift-file}

განსაზღვრეთ target `Project.targets`-ში:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target(
            name: "TargetX",
            destinations: .iOS,
            product: .framework, // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX",
            sources: ["Sources/TargetX/**"],
            dependencies: [
                /** Dependencies go here **/
                /** .external(name: "Kingfisher") **/
                /** .target(name: "OtherProjectTarget") **/
            ],
            settings: .settings(configurations: [
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"),
                .release(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"),
            ])
        ),
    ]
)
```

> [!NOTE]
> **ტესტების სამიზნეები**
>
> თუ target-ს აქვს დაკავშირებული ტესტების target, ისიც უნდა განსაზღვროთ `Project.swift` ფაილში იგივე ნაბიჯების გამეორებით.


### დაადასტურეთ სამიზნის მიგრაცია {#validate-the-target-migration}

გაუშვით `tuist generate`, შემდეგ `xcodebuild build`, რათა დარწმუნდეთ, რომ პროექტი იწყობა, და `tuist test`, რათა დარწმუნდეთ, რომ ტესტები გადის. დამატებით, შეგიძლიათ გამოიყენოთ [xcdiff](https://github.com/bloomberg/xcdiff) გენერირებული Xcode-პროექტის არსებულთან შესადარებლად, რათა დარწმუნდეთ, რომ ცვლილებები სწორია.

### გაიმეორეთ {#repeat}

გაიმეორეთ, სანამ ყველა target სრულად არ გადაიტანთ. დასრულების შემდეგ, გირჩევთ განაახლოთ თქვენი CI და CD პაიპლაინები, რათა პროექტი ააწყოთ და შეამოწმოთ `tuist generate`-ის გამოყენებით, შემდეგ `xcodebuild build` და `tuist test`.

## პრობლემების გადაჭრა {#troubleshooting}

### კომპილაციის შეცდომები დაკარგული ფაილების გამო. {#compilation-errors-due-to-missing-files}

თუ თქვენი Xcode-პროექტის target-ებთან დაკავშირებული ფაილები სრულად არ იყო მოთავსებული ფაილური სისტემის ისეთ დირექტორიაში, რომელიც target-ს წარმოადგენდა, შეიძლება მიიღოთ პროექტი, რომელიც არ იკომპილირდება. დარწმუნდით, რომ Tuist-ით პროექტის გენერირების შემდეგ ფაილების სია ემთხვევა Xcode-პროექტის ფაილების სიას და გამოიყენეთ ეს შესაძლებლობა ფაილების სტრუქტურის target-ის სტრუქტურასთან შესათანხმებლად.
