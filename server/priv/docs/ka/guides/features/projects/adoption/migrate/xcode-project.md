---
{
  "title": "Xcode პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ Xcode პროექტი Tuist-ში."
}
---
# Xcode-ის პროექტის მიგრაცია {#migrate-an-xcode-project}

თუ არ <.localized_link href="/guides/features/projects/adoption/new-project">შექმნით ახალ პროექტს Tuist-ის გამოყენებით</.localized_link>, რა შემთხვევაშიც ყველაფერი ავტომატურად კონფიგურირდება, მოგიწევთ თქვენი Xcode-ის პროექტების განსაზღვრა Tuist-ის პრიმიტივების გამოყენებით. ამ პროცესის სირთულე დამოკიდებულია თქვენი პროექტების სირთულეზე.

როგორც ალბათ იცით, Xcode-ის პროექტები დროთა განმავლობაში შეიძლება გახდეს არეული და რთული: ჯგუფები, რომლებიც არ ემთხვევა დირექტორიის სტრუქტურას, ფაილები, რომლებიც საერთოა რამდენიმე სამიზნისთვის, ან ფაილის მითითებები, რომლებიც არარსებულ ფაილებზე მიუთითებენ (რამდენიმე მაგალითისთვის). ეს დაგროვილი სირთულე გვირთულებს ისეთი ბრძანების მიწოდებას, რომელიც სანდოდ გადაიტანს პროექტს.

გარდა ამისა, ხელით მიგრაცია შესანიშნავი ვარჯიშია თქვენი პროექტების გასასუფთავებლად და გასამარტივებლად. ამისთვის მადლიერები იქნებიან არა მხოლოდ თქვენი პროექტის დეველოპერები, არამედ Xcode-იც, რომელიც უფრო სწრაფად დაამუშავებს და ინდექსირებს მათ. მას შემდეგ, რაც სრულად აითვისებთ Tuist-ს, ის უზრუნველყოფს, რომ პროექტები თანმიმდევრულად იყოს განსაზღვრული და მარტივი დარჩეს.

ამ სამუშაოს გასამარტივებლად, გთავაზობთ რამდენიმე სახელმძღვანელოს, რომელიც ეფუძნება მომხმარებლებისგან მიღებულ გამოხმაურებას.

## პროექტის საწყისი სტრუქტურის შექმნა {#create-project-scaffold}

პირველ რიგში, შექმენით თქვენი პროექტის ჩარჩო შემდეგი Tuist-ის ფაილებით:

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს პროექტს, ხოლო `Package.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს დამოკიდებულებებს. `Tuist.swift` ფაილში შეგიძლიათ განსაზღვროთ Tuist-ის პროექტის დონის პარამეტრები თქვენი პროექტისთვის.

> [!TIP]
> **პროექტის სახელი -Tuist სუფიქსით**
>
> არსებულ Xcode-ის პროექტთან კონფლიქტების თავიდან ასაცილებლად, გირჩევთ პროექტის სახელს დაამატოთ `-Tuist` სუფიქსი. მისი მოცილება შეგიძლიათ მას შემდეგ, რაც სრულად გადაიტანთ თქვენს პროექტს Tuist-ზე.


## Tuist-ის პროექტის აგება და ტესტირება CI-ში {#build-and-test-the-tuist-project-in-ci}

იმის უზრუნველსაყოფად, რომ თითოეული ცვლილების მიგრაცია ვალიდურია, გირჩევთ გააფართოვოთ თქვენი უწყვეტი ინტეგრაცია, რათა ააგოთ და შეამოწმოთ Tuist-ის მიერ თქვენი მანიფესტის ფაილიდან გენერირებული პროექტი:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## პროექტის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-project-build-settings-into-xcconfig-files}

ამოიღეთ აგების პარამეტრები პროექტიდან `.xcconfig` ფაილში, რათა პროექტი უფრო მსუბუქი და ადვილად მიგრირებადი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:


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
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

შემდეგ გააფართოვეთ თქვენი უწყვეტი ინტეგრაციის პაიპლაინი, რათა შეასრულოს შემდეგი ბრძანება და უზრუნველყოს, რომ აგების პარამეტრების ცვლილებები პირდაპირ `.xcconfig` ფაილებში ხდება:

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

> [!TIP]
> **პროდუქტის ტიპები**
>
> შეგიძლიათ გადაწეროთ პროდუქტის ტიპი კონკრეტული პაკეტისთვის `productTypes` სლექტორში `PackageSettings` სტრუქტში დამატებით. ნაგულისხმევად, Tuist ვარაუდობს, რომ ყველა პაკეტი სტატიკური ჩარჩოა.


## მიგრაციის თანმიმდევრობის განსაზღვრა {#determine-the-migration-order}

გირჩევთ სამიზნეების მიგრაცია დაიწყოთ იმით, რომელიც ყველაზე მეტად არის დამოკიდებული, და დაასრულოთ იმით, რომელიც ნაკლებად. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის სამიზნეების ჩამოსათვლელად, დალაგებული დამოკიდებულებების რაოდენობის მიხედვით:

```bash
tuist migration list-targets -p Project.xcodeproj
```

დაიწყეთ სამიზნეების მიგრაცია სიის თავიდან, რადგან ისინი არიან ისინი, ვინზეც ყველაზე მეტად არიან დამოკიდებული.


## მიგრაცია სამიზნეების {#migrate-targets}

გადაიტანეთ სამიზნეები ერთ-ერთად. გირჩევთ თითოეული სამიზნისთვის შექმნათ pull request, რათა უზრუნველყოთ, რომ ცვლილებები განიხილება და შემოწმდება მათ შერწყმამდე.

### ამოიღეთ სამიზნის აგების პარამეტრები `.xcconfig` ფაილებში {#extract-the-target-build-settings-into-xcconfig-files}

როგორც პროექტის აგების პარამეტრების შემთხვევაში, ამოიღეთ სამიზნის აგების პარამეტრები `.xcconfig` ფაილში, რათა სამიზნე უფრო მსუბუქი და ადვილად მიგრირებადი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება სამიზნიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### განსაზღვრეთ სამიზნე `Project.swift` ფაილში {#define-the-target-in-the-projectswift-file}

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
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

> [!NOTE]
> **ტესტების ტარგეტები**
>
> თუ სამიზნეს აქვს ასოცირებული ტესტების სამიზნე, უნდა განსაზღვროთ ის ასევე `Project.swift` ფაილში, იგივე ნაბიჯების გამეორებით.


### დაადასტურეთ სამიზნის მიგრაცია {#validate-the-target-migration}

შეასრულეთ `tuist generate`, შემდეგ `xcodebuild build`, რათა უზრუნველყოთ პროექტის აგება, და `tuist test`, რათა უზრუნველყოთ ტესტების წარმატებით გავლა. დამატებით, შეგიძლიათ გამოიყენოთ [xcdiff](https://github.com/bloomberg/xcdiff) გენერირებული Xcode-ის პროექტის არსებულთან შესადარებლად, რათა უზრუნველყოთ, რომ ცვლილებები სწორია.

### გაიმეორეთ {#repeat}

გაიმეორეთ, სანამ ყველა სამიზნე სრულად არ გადაიტანება. როცა დაასრულებთ, გირჩევთ განაახლოთ თქვენი CI და CD პაიპლაინები, რათა ააგოთ და შეამოწმოთ პროექტი `tuist generate`-ის გამოყენებით, შემდეგ `xcodebuild build` და `tuist test`.

## პრობლემების გადაჭრა {#troubleshooting}

### კომპილაციის შეცდომები დაკარგული ფაილების გამო. {#compilation-errors-due-to-missing-files}

თუ თქვენი Xcode-ის პროექტის სამიზნეებთან ასოცირებული ფაილები არ იყო მოთავსებული ფაილური სისტემის დირექტორიაში, რომელიც წარმოადგენს სამიზნეს, შეიძლება მიიღოთ პროექტი, რომელიც არ კომპილირდება. დარწმუნდით, რომ ფაილების სია Tuist-ით პროექტის გენერირების შემდეგ ემთხვევა ფაილების სიას Xcode-ის პროექტში, და გამოიყენეთ ეს შესაძლებლობა ფაილის სტრუქტურის სამიზნის სტრუქტურასთან შესათანხმებლად.
