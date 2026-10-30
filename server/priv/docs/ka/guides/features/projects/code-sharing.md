---
{
  "title": "კოდის გაზიარება",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გააზიაროთ კოდი მანიფესტის ფაილებში დუბლირების შესამცირებლად და თანმიმდევრულობის უზრუნველსაყოფად"
}
---
# კოდის გაზიარება {#code-sharing}

Xcode-ს ერთ-ერთი უხერხულობა დიდ პროექტებთან მუშაობისას არის ის, რომ ის არ იძლევა პროექტის ელემენტების ხელახლა გამოყენების საშუალებას, გარდა აგების პარამეტრებისა, `.xcconfig` ფაილების მეშვეობით. პროექტის განმარტებების ხელახლა გამოყენება სასარგებლოა შემდეგი მიზეზების გამო:

- ამარტივებს **მოვლას**, რადგან ცვლილებები შეიძლება ერთ ადგილას განხორციელდეს და ყველა პროექტი ავტომატურად მიიღებს ამ ცვლილებებს.
- საშუალებას იძლევა განვსაზღვროთ **კონვენციები**, რომლებსაც ახალი პროექტები დაემორჩილებიან.
- პროექტები უფრო **თანმიმდევრულია** და, შესაბამისად, თანმიმდევრულობის ნაკლებობის გამო აგების ჩავარდნის ალბათობა მნიშვნელოვნად მცირდება.
- ახალი პროექტის დამატება მარტივ ამოცანად იქცევა, რადგან შეგვიძლია არსებული ლოგიკის ხელახლა გამოყენება.

კოდის ხელახლა გამოყენება მანიფესტის ფაილებში Tuist-ში შესაძლებელია **პროექტის აღწერის დამხმარეების** კონცეფციის წყალობით.

> [!TIP]
> **Tuist-ის უნიკალური უპირატესობა**
>
> ბევრი ორგანიზაცია მოსწონს Tuist, რადგან ისინი პროექტის აღწერის დამხმარეებში ხედავენ პლატფორმას, რომლის მეშვეობითაც პლატფორმის გუნდებს შეუძლიათ საკუთარი კონვენციების კოდირება და პროექტების აღწერისთვის საკუთარი ენის შექმნა. მაგალითად, YAML-ზე დაფუძნებულ პროექტების გენერატორებს უნდა შეიმუშაონ საკუთარი YAML-ზე დაფუძნებული პროპრიეტარული შაბლონიზაციის გადაწყვეტა, ან აიძულონ ორგანიზაციები მათ საფუძველზე ააგონ საკუთარი ინსტრუმენტები.


## პროექტის აღწერის დამხმარეები {#project-description-helpers}

პროექტის აღწერის დამხმარეები არის Swift ფაილები, რომლებიც კომპილირდება მოდულად, `ProjectDescriptionHelpers`, რომლის იმპორტირებაც მანიფესტის ფაილებს შეუძლიათ. მოდული კომპილირდება `Tuist/ProjectDescriptionHelpers` დირექტორიაში არსებული ყველა ფაილის შეკრებით.

შეგიძლიათ მათი იმპორტირება თქვენს მანიფესტის ფაილში ფაილის თავში import განცხადების დამატებით:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` ხელმისაწვდომია შემდეგ მანიფესტებში:
- `Project.swift`
- `Package.swift` (მხოლოდ `#TUIST` კომპილატორის დროშის უკან)
- `Workspace.swift`

## მაგალითი {#example}

ქვემოთ მოცემულ ფრაგმენტებში ნაჩვენებია მაგალითი, თუ როგორ ვაფართოებთ `Project` მოდელს სტატიკური კონსტრუქტორების დასამატებლად და როგორ ვიყენებთ მათ `Project.swift` ფაილიდან:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

> [!TIP]
> **ინსტრუმენტი კონვენციების დასამკვიდრებლად**
>
> დააკვირდით, როგორ ვაფიქსირებთ ფუნქციის მეშვეობით კონვენციებს სამიზნეების სახელების, ბანდლის იდენტიფიკატორის და საქაღალდეების სტრუქტურის შესახებ.
