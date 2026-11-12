---
{
  "title": "Xcode პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ Xcode პროექტი Tuist პროექტზე."
}
---
# Xcode-პროექტის მიგრაცია {#migrate-an-xcode-project}

თუ არ <.localized_link href="/guides/features/projects/adoption/new-project">შექმნით ახალ პროექტს Tuist-ის გამოყენებით</.localized_link>, რა შემთხვევაშიც ყველაფერი ავტომატურად კონფიგურირდება, თქვენ მოგიწევთ Xcode-პროექტების განსაზღვრა Tuist-ის პრიმიტივების გამოყენებით. ამ პროცესის სირთულე დამოკიდებულია თქვენი პროექტების სირთულეზე.

როგორც ალბათ იცით, Xcode-პროექტები დროთა განმავლობაში შეიძლება გახდეს არეული და რთული: ჯგუფები, რომლებიც არ ემთხვევა დირექტორიების სტრუქტურას, ფაილები, რომლებიც საერთოა რამდენიმე სამიზნესთვის, ან ფაილის მითითებები, რომლებიც არარსებულ ფაილებზე მიუთითებენ (რამდენიმე მაგალითი). ეს დაგროვილი სირთულე გვირთულებს ისეთი ბრძანების შეთავაზებას, რომელიც პროექტს საიმედოდ გადაიტანს.

უფრო მეტიც, ხელით მიგრაცია შესანიშნავი ვარჯიშია თქვენი პროექტების გასასუფთავებლად და გასამარტივებლად. ამისთვის მადლიერები იქნებიან არა მხოლოდ თქვენი პროექტის დეველოპერები, არამედ Xcode-ც, რომელიც უფრო სწრაფად დაამუშავებს და დააინდექსებს მათ. როგორც კი სრულად გადახვალთ Tuist-ზე, ის უზრუნველყოფს, რომ პროექტები თანმიმდევრულად იყოს განსაზღვრული და მარტივი დარჩეს.

ამ სამუშაოს გასამარტივებლად, ჩვენ გაძლევთ რამდენიმე მითითებას, რომელიც დაფუძნებულია მომხმარებლებისგან მიღებულ გამოხმაურებაზე.

## პროექტის საფუძვლის შექმნა {#create-project-scaffold}

პირველ რიგში, შექმენით თქვენი პროექტის შაბლონი შემდეგი Tuist-ფაილების გამოყენებით:

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

`Project.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს პროექტს, ხოლო `Package.swift` არის მანიფესტის ფაილი, სადაც განსაზღვრავთ თქვენს დამოკიდებულებებს. `Tuist.swift` ფაილში შეგიძლიათ განსაზღვროთ პროექტის დონის Tuist-პარამეტრები თქვენი პროექტისთვის.

> [!TIP]
> **პროექტის სახელი -Tuist სუფიქსით**
>
> არსებულ Xcode-პროექტთან კონფლიქტების თავიდან ასაცილებლად, რეკომენდებულია პროექტის სახელს დაამატოთ `-Tuist` სუფიქსი. მისი წაშლა შეგიძლიათ მას შემდეგ, რაც სრულად გადაიტანთ თქვენს პროექტს Tuist-ზე.


## Tuist-პროექტის აგება და ტესტირება CI-ში {#build-and-test-the-tuist-project-in-ci}

იმის უზრუნველსაყოფად, რომ თითოეული ცვლილების მიგრაცია ვალიდურია, რეკომენდებულია გააფართოვოთ თქვენი უწყვეტი ინტეგრაცია (CI) ისე, რომ ააწყოთ და შეამოწმოთ Tuist-ის მიერ თქვენი მანიფესტის ფაილიდან გენერირებული პროექტი:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## პროექტის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-project-build-settings-into-xcconfig-files}

ამოიღეთ აგების პარამეტრები პროექტიდან `.xcconfig` ფაილში, რათა პროექტი უფრო მსუბუქი და მიგრაციისთვის უფრო მარტივი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

შემდეგ განაახლეთ თქვენი `Project.swift` ფაილი ისე, რომ მიუთითებდეს ახლად შექმნილ `.xcconfig` ფაილზე:

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

შემდეგ გააფართოვთ თქვენი უწყვეტი ინტეგრაციის (CI) პაიპლაინი ისე, რომ შეასრულოს შემდეგი ბრძანება და უზრუნველყოს, რომ აგების პარამეტრების ცვლილებები პირდაპირ `.xcconfig` ფაილებში ხდება:

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
> შეგიძლიათ გადაწეროთ პროდუქტის ტიპი კონკრეტული პაკეტისთვის `productTypes` სლოვარში დამატებით `PackageSettings` სტრუქტურაში. ნაგულისხმევად, Tuist ვარაუდობს, რომ ყველა პაკეტი სტატიკური ფრეიმვორკია.


## მიგრაციის თანმიმდევრობის განსაზღვრა {#determine-the-migration-order}

რეკომენდებულია სამიზნეების მიგრაცია იმ სამიზნიდან, რომელიც ყველაზე მეტად არის დამოკიდებული, იმისკენ, რომელიც ნაკლებად. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება პროექტის სამიზნეების ჩამოსათვლელად, დალაგებული დამოკიდებულებების რაოდენობის მიხედვით:

```bash
tuist migration list-targets -p Project.xcodeproj
```

დაიწყეთ სამიზნეების მიგრაცია სიის თავიდან, რადგან ისინი არიან ისინი, ვინზეც ყველაზე მეტად არიან დამოკიდებულნი.


## სამიზნეების მიგრაცია {#migrate-targets}

გადაიტანეთ სამიზნეები ერთ-ერთად. რეკომენდებულია თითოეული სამიზნისთვის pull request-ის გაკეთება, რათა უზრუნველყოთ, რომ ცვლილებები განიხილება და შემოწმდება მათ შერწყმამდე.

### სამიზნის აგების პარამეტრების ამოღება `.xcconfig` ფაილებში {#extract-the-target-build-settings-into-xcconfig-files}

როგორც პროექტის აგების პარამეტრების შემთხვევაში, ამოიღეთ სამიზნის აგების პარამეტრები `.xcconfig` ფაილში, რათა სამიზნე უფრო მსუბუქი და მიგრაციისთვის უფრო მარტივი გახდეს. შეგიძლიათ გამოიყენოთ შემდეგი ბრძანება სამიზნიდან აგების პარამეტრების `.xcconfig` ფაილში ამოსაღებად:

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
> **ტესტების სამიზნეები**
>
> თუ სამიზნეს აქვს დაკავშირებული ტესტების სამიზნე, უნდა განსაზღვროთ ის ასევე `Project.swift` ფაილში იგივე ნაბიჯების გამეორებით.


### სამიზნის მიგრაციის ვალიდაცია {#validate-the-target-migration}

შეასრულეთ `tuist generate`, შემდეგ `xcodebuild build`, რათა უზრუნველყოთ პროექტის აწყობა, და `tuist test`, რათა უზრუნველყოთ ტესტების წარმატებით გავლა. დამატებით, შეგიძლიათ გამოიყენოთ [xcdiff](https://github.com/bloomberg/xcdiff) გენერირებული Xcode-პროექტის არსებულთან შესადარებლად, რათა უზრუნველყოთ, რომ ცვლილებები სწორია.

### გამეორება {#repeat}

გაიმეორეთ, სანამ ყველა სამიზნე სრულად არ გადაიტანება. როგორც კი დაასრულებთ, რეკომენდებულია განაახლოთ თქვენი CI და CD პაიპლაინები, რათა ააწყოთ და შეამოწმოთ პროექტი `tuist generate`-ის გამოყენებით, შემდეგ `xcodebuild build` და `tuist test`.

## პრობლემების გადაჭრა {#troubleshooting}

### კომპილაციის შეცდომები გამოტოვებული ფაილების გამო. {#compilation-errors-due-to-missing-files}

თუ თქვენი Xcode-პროექტის სამიზნეებთან დაკავშირებული ფაილები სრულად არ იყო მოთავსებული ფაილური სისტემის დირექტორიაში, რომელიც წარმოადგენს სამიზნეს, შეიძლება მიიღოთ პროექტი, რომელიც არ კომპილირდება. დარწმუნდით, რომ ფაილების სია Tuist-ით პროექტის გენერირების შემდეგ ემთხვევა Xcode-პროექტში ფაილების სიას და ისარგებლეთ შესაძლებლობით, გაასწოროთ ფაილების სტრუქტურა სამიზნის სტრუქტურასთან.
