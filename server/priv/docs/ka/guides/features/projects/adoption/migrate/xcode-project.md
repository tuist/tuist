---
{
  "title": "Xcode-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ Xcode-ის პროექტი Tuist-ის პროექტში."
}
---
# Xcode-ის პროექტის მიგრაცია {#migrate-an-xcode-project}

თუ არ <.localized_link href="/guides/features/projects/adoption/new-project">შექმნით ახალ პროექტს Tuist-ის გამოყენებით</.localized_link>, რა შემთხვევაშიც ყველაფერი ავტომატურად კონფიგურირდება, მოგიწევთ თქვენი Xcode-ის პროექტების განსაზღვრა Tuist-ის პრიმიტივების საშუალებით. ამ პროცესის სირთულე დამოკიდებულია თქვენი პროექტების სირთულეზე.

როგორც ალბათ იცით, Xcode-ის პროექტები დროთა განმავლობაში შეიძლება გახდეს არეული და რთული: ჯგუფები, რომლებიც არ ემთხვევა დირექტორიების სტრუქტურას, ფაილები, რომლებიც გაზიარებულია ტარგეტებს შორის, ან ფაილის მითითებები, რომლებიც მიუთითებენ არარსებულ ფაილებზე (რამდენიმე მაგალითის ჩასახელებლად). ეს დაგროვილი სირთულე გვირთულებს ისეთი ბრძანების უზრუნველყოფას, რომელიც საიმედოდ გადაიტანს პროექტს.

გარდა ამის, ხელით მიგრაცია შესანიშნავი ვარჯიშია თქვენი პროექტების გასასუფთავებლად და გასამარტივებლად. არა მხოლოდ თქვენს პროექტში მომუშავე დეველოპერები იქნებიან მადლიერები ამისთვის, არამედ Xcode-იც, რომელიც უფრო სწრაფად დაამუშავებს და დააინდექსებს მათ. მას შემდეგ, რაც სრულად გადახვალთ Tuist-ზე, ის უზრუნველყოფს, რომ პროექტები თანმიმდევრულად იყოს განსაზღვრული და მარტივი დარჩეს.

ამ სამუშაოს გასამარტივებლად, გთავაზობთ რამდენიმე რეკომენდაციას, რომელიც დაფუძნებულია მომხმარებლებისგან მიღებულ უკუკავშირზე.

## პროექტის სკაფოლდის შექმნა {#create-project-scaffold}

უპირველეს ყოვლისა, შექმენით თქვენი პროექტის სკელეტი შემდეგი Tuist ფაილებით:

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

`Project.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს პროექტს, ხოლო `Package.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს დამოკიდებულებებს. `Tuist.swift` ფაილში შეგიძლიათ განსაზღვროთ პროექტის დონის Tuist პარამეტრები თქვენი პროექტისთვის.

> [!TIP]
> **პროექტის სახელი -Tuist სუფიქსით**
>
> არსებულ Xcode-ის პროექტთან კონფლიქტების თავიდან ასაცილებლად, გირჩევთ პროექტის სახელს დაამატოთ `-Tuist` სუფიქსი. მისი მოცილება შეგიძლიათ მას შემდეგ, რაც სრულად გადაიტანთ თქვენს პროექტს Tuist-ზე.


## Tuist-ის პროექტის აგება და ტესტირება CI-ში {#build-and-test-the-tuist-project-in-ci}

იმის უზრუნველსაყოფად, რომ თითოეული ცვლილების მიგრაცია ვალიდურია, გირჩევთ გააფართოვოთ თქვენი უწყვეტი ინტეგრაცია (CI), რათა ააგოთ და შეამოწმოთ Tuist-ის მიერ თქვენი მანიფესტის ფაილიდან გენერირებული პროექტი:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## პროექტის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-project-build-settings-into-xcconfig-files}

ამოიღეთ აგების პარამეტრები პროექტიდან `.xcconfig` ფაილში, რათა პროექტი უფრო მსუბუქი და მიგრაციისთვის ადვილი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:


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

შემდეგ გააფართოვთ თქვენი უწყვეტი ინტეგრაციის (CI) პაიპლაინი, რათა შეასრულოს შემდეგი ბრძანება და უზრუნველყოს, რომ აგების პარამეტრების ცვლილებები პირდაპირ `.xcconfig` ფაილებში ხდება:

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
> შეგიძლიათ გადაწეროთ პროდუქტის ტიპი კონკრეტული პაკეტისთვის `productTypes` ლექსიკონში დამატებით `PackageSettings` სტრუქტურაში. ნაგულისხმევად, Tuist ვარაუდობს, რომ ყველა პაკეტი სტატიკური ფრეიმვორკია.


## მიგრაციის თანმიმდევრობის განსაზღვრა {#determine-the-migration-order}

გირჩევთ ტარგეტების მიგრაცია დაიწყოთ იმით, რომელიც ყველაზე მეტად არის დამოკიდებული, და დაასრულოთ იმით, რომელიც ყველაზე ნაკლებად. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის ტარგეტების ჩამოსათვლელად, დალაგებული დამოკიდებულებების რაოდენობის მიხედვით:

```bash
tuist migration list-targets -p Project.xcodeproj
```

დაიწყეთ ტარგეტების მიგრაცია სიის თავიდან, რადგან ისინი არიან ისინი, ვინზეც ყველაზე მეტად არიან დამოკიდებულნი.


## სამიზნეების (targets) მიგრაცია {#migrate-targets}

გადაიტანეთ ტარგეტები ერთ-ერთი. გირჩევთ თითოეული ტარგეტისთვის შექმნათ pull request, რათა უზრუნველყოთ, რომ ცვლილებები განიხილება და შემოწმდება მათ შერწყმამდე.

### სამიზნის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-target-build-settings-into-xcconfig-files}

როგორც პროექტის აგების პარამეტრების შემთხვევაში, ამოიღეთ ტარგეტის აგების პარამეტრები `.xcconfig` ფაილში, რათა ტარგეტი უფრო მსუბუქი და მიგრაციისთვის ადვილი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება ტარგეტიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### სამიზნის განსაზღვრა `Project.swift` ფაილში {#define-the-target-in-the-projectswift-file}

განსაზღვრეთ ტარგეტი `Project.targets`-ში:

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
> თუ ტარგეტს აქვს დაკავშირებული ტესტის ტარგეტი, ისიც უნდა განსაზღვროთ `Project.swift` ფაილში იგივე ნაბიჯების გამეორებით.


### სამიზნის მიგრაციის ვალიდაცია {#validate-the-target-migration}

შეასრულეთ `tuist generate`, შემდეგ `xcodebuild build`, რათა დარწმუნდეთ, რომ პროექტი იგება, და `tuist test`, რათა დარწმუნდეთ, რომ ტესტები გადის. დამატებით, შეგიძლიათ გამოიყენოთ [xcdiff](https://github.com/bloomberg/xcdiff) გენერირებული Xcode-ის პროექტის არსებულთან შესადარებლად, რათა დარწმუნდეთ, რომ ცვლილებები სწორია.

### გაიმეორეთ {#repeat}

გაიმეორეთ, სანამ ყველა ტარგეტი სრულად არ გადაიტანება. როდესაც დაასრულებთ, გირჩევთ განაახლოთ თქვენი CI და CD პაიპლაინები, რათა ააგოთ და შეამოწმოთ პროექტი `tuist generate`-ის გამოყენებით, შემდეგ `xcodebuild build` და `tuist test`.

## პრობლემების გადაჭრა {#troubleshooting}

### კომპილაციის შეცდომები გამოტოვებული ფაილების გამო. {#compilation-errors-due-to-missing-files}

თუ თქვენი Xcode-ის პროექტის ტარგეტებთან დაკავშირებული ფაილები არ იყო მოთავსებული ფაილური სისტემის დირექტორიაში, რომელიც წარმოადგენს ტარგეტს, შეიძლება მიიღოთ პროექტი, რომელიც არ კომპილირდება. დარწმუნდით, რომ ფაილების სია Tuist-ით პროექტის გენერირების შემდეგ ემთხვევა Xcode-ის პროექტში ფაილების სიას და ისარგებლეთ შესაძლებლობით, გაასწოროთ ფაილების სტრუქტურა ტარგეტის სტრუქტურასთან.
