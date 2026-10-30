---
{
  "title": "კოდის გაზიარება",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გააზიაროთ კოდი მანიფესტის ფაილებს შორის დუბლირების შესამცირებლად და თანმიმდევრულობის უზრუნველსაყოფად"
}
---
# კოდის გაზიარება {#code-sharing}

Xcode-ის ერთ-ერთი უხერხულობა დიდ პროექტებთან მუშაობისას არის ის, რომ ის არ იძლევა პროექტის ელემენტების ხელახლა გამოყენების საშუალებას ბილდის პარამეტრების გარდა `.xcconfig` ფაილების მეშვეობით. პროექტის განსაზღვრებების ხელახლა გამოყენება სასარგებლოა შემდეგი მიზეზების გამო:

- ამარტივებს **მომსახურებას**, რადგან ცვლილებები შეიძლება განხორციელდეს ერთ ადგილას და ყველა პროექტი ავტომატურად მიიღებს ამ ცვლილებებს.
- საშუალებას იძლევა განვსაზღვროთ **შეთანხმებები**, რომლებსაც ახალი პროექტები შეუძლიათ დაემორჩილონ.
- პროექტები უფრო **თანმიმდევრულია** და შესაბამისად, შეუსაბამობებით გამოწვეული ბილდის ჩავარდნის ალბათობა მნიშვნელოვნად მცირდება.
- ახალი პროექტის დამატება მარტივ ამოცანად იქცევა, რადგან შეგვიძლია ხელახლა გამოვიყენოთ არსებული ლოგიკა.

კოდის ხელახლა გამოყენება მანიფესტის ფაილებში Tuist-ში შესაძლებელია **პროექტის აღწერის დამხმარეების** კონცეფციის წყალობით.

> [!TIP]
> **Tuist-ის უნიკალური უპირატესობა**
>
> ბევრ ორგანიზაციას მოსწონს Tuist, რადგან ისინი პროექტის აღწერის დამხმარეებში ხედავენ პლატფორმას პლატფორმის გუნდებისთვის, რათა დააკოდიფიცირონ საკუთარი შეთანხმებები და შექმნან საკუთარი ენა პროექტების აღსაწერად. მაგალითად, YAML-ზე დაფუძნებულ პროექტის გენერატორებს უნდა შეიმუშაონ საკუთარი YAML-ზე დაფუძნებული პროპრიეტარული შაბლონიზაციის გადაწყვეტა, ან აიძულონ ორგანიზაციები ააშენონ საკუთარი ინსტრუმენტები მათზე.


## პროექტის აღწერის დამხმარეები {#project-description-helpers}

პროექტის აღწერის დამხმარეები არის Swift ფაილები, რომლებიც კომპილირდება მოდულად, `ProjectDescriptionHelpers`, რომლის იმპორტირებაც მანიფესტის ფაილებს შეუძლიათ. მოდული კომპილირდება `Tuist/ProjectDescriptionHelpers` დირექტორიაში არსებული ყველა ფაილის შეგროვებით.

შეგიძლიათ მათი იმპორტირება თქვენს მანიფესტის ფაილში import განცხადების დამატებით ფაილის თავში:

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

ქვემოთ მოყვანილი ფრაგმენტები შეიცავს მაგალითს, თუ როგორ ვაფართოებთ `Project` მოდელს სტატიკური კონსტრუქტორების დასამატებლად და როგორ ვიყენებთ მათ `Project.swift` ფაილიდან:

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
> **ინსტრუმენტი შეთანხმებების დასამყარებლად**
>
> დააკვირდით, როგორ განვსაზღვრავთ ფუნქციის მეშვეობით შეთანხმებებს სამიზნეების სახელების, ბანდლის იდენტიფიკატორის და საქაღალდეების სტრუქტურის შესახებ.
