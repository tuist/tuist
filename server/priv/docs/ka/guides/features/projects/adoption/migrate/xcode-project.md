---
{
  "title": "Xcode პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ Xcode პროექტი Tuist-ზე."
}
---
# Xcode-პროექტის მიგრაცია {#migrate-an-xcode-project}

თუ არ <.localized_link href="/guides/features/projects/adoption/new-project">ქმნით ახალ პროექტს Tuist-ის გამოყენებით</.localized_link>, რა შემთხვევაშიც ყველაფერი ავტომატურად კონფიგურირდება, თქვენ მოგიწევთ Xcode-პროექტების განსაზღვრა Tuist-ის პრიმიტივების გამოყენებით. ამ პროცესის სირთულე დამოკიდებულია თქვენი პროექტების სირთულეზე.

როგორც ალბათ იცით, Xcode-პროექტები დროთა განმავლობაში შეიძლება გახდეს არაორგანიზებული და რთული: ჯგუფები, რომლებიც არ ემთხვევა დირექტორიის სტრუქტურას, ფაილები, რომლებიც საერთოა რამდენიმე სამიზნეს შორის, ან ფაილის ბმულები, რომლებიც მიუთითებენ არარსებულ ფაილებზე (რამდენიმე მაგალითისთვის). ეს დაგროვილი სირთულე გვირთულებს ისეთი ბრძანების შეთავაზებას, რომელიც სანდოდ გადაიტანს პროექტს.

უფრო მეტიც, ხელით მიგრაცია შესანიშნავი ვარჯიშია თქვენი პროექტების გასაწმენდად და გასამარტივებლად. ამისთვის მადლიერები იქნებიან არა მხოლოდ თქვენი პროექტის დეველოპერები, არამედ Xcode-ც, რომელიც უფრო სწრაფად დაამუშავებს და ინდექსირებს მათ. მას შემდეგ, რაც სრულად გადახვალთ Tuist-ზე, ის უზრუნველყოფს, რომ პროექტები თანმიმდევრულად იყოს განსაზღვრული და მარტივი დარჩეს.

ამ სამუშაოს გასამარტივებლად, გთავაზობთ რამდენიმე სახელმძღვანელოს, რომელიც ეფუძნება მომხმარებლებისგან მიღებულ გამოხმაურებას.

## პროექტის ჩარჩოს შექმნა {#create-project-scaffold}

პირველ რიგში, შექმენით თქვენი პროექტის ჩარჩო შემდეგი Tuist-ფაილებით:

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

`Project.swift` არის მანიფესტური ფაილი, სადაც განსაზღვრავთ თქვენს პროექტს, ხოლო `Package.swift` არის მანიფესტური ფაილი, სადაც განსაზღვრავთ თქვენს დამოკიდებულებებს. `Tuist.swift` ფაილში შეგიძლიათ განსაზღვროთ Tuist-ის პარამეტრები თქვენი პროექტისთვის.

> [!TIP]
> **პროექტის სახელი -Tuist სუფიქსით**
>
> არსებულ Xcode-პროექტთან კონფლიქტების თავიდან ასაცილებლად, გირჩევთ პროექტის სახელს დაამატოთ `-Tuist` სუფიქსი. მისი მოცილება შეგიძლიათ მას შემდეგ, რაც სრულად გადაიტანთ თქვენს პროექტს Tuist-ზე.


## Tuist-პროექტის აგება და ტესტირება CI-ში {#build-and-test-the-tuist-project-in-ci}

იმის უზრუნველსაყოფად, რომ თითოეული ცვლილების მიგრაცია ვალიდურია, გირჩევთ გააფართოვოთ თქვენი უწყვეტი ინტეგრაცია, რათა ააგოთ და შეამოწმოთ Tuist-ის მიერ თქვენი მანიფესტური ფაილიდან გენერირებული პროექტი:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## პროექტის აგების პარამეტრების `.xcconfig` ფაილებში გადატანა {#extract-the-project-build-settings-into-xcconfig-files}

გადაიტანეთ აგების პარამეტრები პროექტიდან `.xcconfig` ფაილში, რათა პროექტი იყოს უფრო მარტივი და ადვილად გადასატანი. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის აგების პარამეტრების `.xcconfig` ფაილში გადასატანად:


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

შემდეგ გააფართოვთ თქვენი უწყვეტი ინტეგრაციის პაიპლაინი, რათა შეასრულოს შემდეგი ბრძანება და უზრუნველყოს, რომ აგების პარამეტრების ცვლილებები პირდაპირ `.xcconfig` ფაილებში ხდება:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## პაკეტის დამოკიდებულებების გამოყოფა {#extract-package-dependencies}

გადაიტანეთ თქვენი პროექტის ყველა დამოკიდებულება `Tuist/Package.swift` ფაილში:

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
> შეგიძლიათ გადაწეროთ პროდუქტის ტიპი კონკრეტული პაკეტისთვის, თუ დაამატებთ მას `productTypes` ლექსიკონში `PackageSettings` სტრუქტში. ნაგულისხმევად, Tuist ვარაუდობს, რომ ყველა პაკეტი სტატიკური ფრეიმვორკია.


## მიგრაციის თანმიმდევრობის განსაზღვრა {#determine-the-migration-order}

გირჩევთ სამიზნეების მიგრაცია იმის მიხედვით, თუ რომელია ყველაზე მეტად დამოკიდებული სხვებზე, ნაკლებად დამოკიდებულისკენ. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის სამიზნეების ჩამოსათვლელად, დალაგებული დამოკიდებულებების რაოდენობის მიხედვით:

```bash
tuist migration list-targets -p Project.xcodeproj
```

დაიწყეთ სამიზნეების მიგრაცია სიის თავიდან, რადგან ისინი არიან ისინი, ვინც ყველაზე მეტად არიან დამოკიდებულები.


## სამიზნეების მიგრაცია {#migrate-targets}

გადაიტანეთ სამიზნეები ერთ-ერთად. გირჩევთ თითოეული სამიზნისთვის შექმნათ pull request, რათა უზრუნველყოთ, რომ ცვლილებები განიხილება და შემოწმდება მათ შერწყმამდე.

### სამიზნის აგების პარამეტრების `.xcconfig` ფაილებში გადატანა {#extract-the-target-build-settings-into-xcconfig-files}

როგორც პროექტის აგების პარამეტრების შემთხვევაში, გადაიტანეთ სამიზნის აგების პარამეტრები `.xcconfig` ფაილში, რათა სამიზნე იყოს უფრო მარტივი და ადვილად გადასატანი. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება სამიზნის აგების პარამეტრების `.xcconfig` ფაილში გადასატანად:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### სამიზნის განსაზღვრა `Project.swift` ფაილში {#define-the-target-in-the-projectswift-file}

განსაზღვრეთ სამიზნე `Project.targets`-ში:

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
> **ტესტის სამიზნეები**
>
> თუ სამიზნეს აქვს დაკავშირებული ტესტის სამიზნე, უნდა განსაზღვროთ ის ასევე `Project.swift` ფაილში, იმავე ნაბიჯების გამეორებით.


### სამიზნის მიგრაციის ვალიდაცია {#validate-the-target-migration}

შეასრულეთ `tuist generate`, შემდეგ `xcodebuild build`, რათა უზრუნველყოთ პროექტის აგება, და `tuist test`, რათა უზრუნველყოთ ტესტების წარმატებით შესრულება. დამატებით, შეგიძლიათ გამოიყენოთ [xcdiff](https://github.com/bloomberg/xcdiff) გენერირებული Xcode-პროექტის არსებულთან შესადარებლად, რათა უზრუნველყოთ, რომ ცვლილებები სწორია.

### გაიმეორეთ {#repeat}

გაიმეორეთ, სანამ ყველა სამიზნე სრულად არ გადაიტანება. როდესაც დაასრულებთ, გირჩევთ განაახლოთ თქვენი CI და CD პაიპლაინები, რათა ააგოთ და შეამოწმოთ პროექტი `tuist generate`-ის გამოყენებით, შემდეგ `xcodebuild build` და `tuist test`.

## პრობლემების აღმოფხვრა {#troubleshooting}

### კომპილაციის შეცდომები გამოტოვებული ფაილების გამო. {#compilation-errors-due-to-missing-files}

თუ თქვენი Xcode-პროექტის სამიზნეებთან დაკავშირებული ფაილები არ იყო მოთავსებული ფაილური სისტემის დირექტორიაში, რომელიც წარმოადგენს სამიზნეს, შეიძლება მიიღოთ პროექტი, რომელიც არ კომპილირდება. დარწმუნდით, რომ ფაილების სია Tuist-ით პროექტის გენერირების შემდეგ ემთხვევა Xcode-პროექტში არსებულ ფაილების სიას და გამოიყენეთ ეს შესაძლებლობა ფაილების სტრუქტურის სამიზნის სტრუქტურასთან შესათანხმებლად.
