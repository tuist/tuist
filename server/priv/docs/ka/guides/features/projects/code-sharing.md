---
{
  "title": "კოდის გაზიარება",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გააზიაროთ კოდი მანიფესტის ფაილებში გამეორებების შესამცირებლად და თანმიმდევრულობის უზრუნველსაყოფად"
}
---
# კოდის გაზიარება {#code-sharing}

Xcode-ის ერთ-ერთი ნაკლი დიდ პროექტებთან მუშაობისას არის ის, რომ ის საშუალებას არ იძლევა ხელახლა გამოვიყენოთ პროექტის ელემენტები აგების პარამეტრების გარდა `.xcconfig` ფაილების მეშვეობით. პროექტის განმარტებების ხელახლა გამოყენება სასარგებლოა შემდეგი მიზეზების გამო:

- ამარტივებს **მოვლას**, რადგან ცვლილებების ერთ ადგილას გამოყენება შესაძლებელია და ყველა პროექტი ავტომატურად იღებს ამ ცვლილებებს.
- საშუალებას იძლევა განვსაზღვროთ **შეთანხმებები**, რომლებსაც ახალი პროექტები შეესაბამება.
- პროექტები უფრო **თანმიმდევრულია** და, შესაბამისად, თანმიმდევრულობის დარღვევის გამო აგების ჩავარდნის ალბათობა მნიშვნელოვნად მცირდება.
- ახალი პროექტების დამატება მარტივ ამოცანად იქცევა, რადგან არსებული ლოგიკის ხელახლა გამოყენება შეგვიძლია.

Tuist-ში მანიფესტის ფაილებში კოდის ხელახლა გამოყენება შესაძლებელია **პროექტის აღწერის დამხმარეების** კონცეფციის წყალობით.

> [!TIP]
> **Tuist-ის უნიკალური უპირატესობა**
>
> ბევრ ორგანიზაციას მოსწონს Tuist, რადგან ისინი პროექტის აღწერის დამხმარეებში ხედავენ პლატფორმას, რომლითაც პლატფორმის გუნდებს შეუძლიათ თავიანთი შეთანხმებები კოდში ჩაწერონ და პროექტების აღსაწერად საკუთარი ენა შეიმუშაონ. მაგალითად, YAML-ზე დაფუძნებულ პროექტების გენერატორებს უწევთ საკუთარი YAML-ზე დაფუძნებული პროპრიეტარული შაბლონიზაციის გადაწყვეტის შექმნა, ან ორგანიზაციებს აიძულებენ საკუთარი ინსტრუმენტები მათ საფუძველზე ააგონ.


## პროექტის აღწერის დამხმარეები {#project-description-helpers}

პროექტის აღწერის დამხმარეები არის Swift ფაილები, რომლებიც კომპილირდება მოდულად, `ProjectDescriptionHelpers`, რომლის იმპორტიც მანიფესტის ფაილებს შეუძლიათ. მოდული კომპილირდება `Tuist/ProjectDescriptionHelpers` დირექტორიაში არსებული ყველა ფაილის შეკრებით.

მათი იმპორტი მანიფესტის ფაილში შესაძლებელია ფაილის თავში import განცხადების დამატებით:

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

ქვემოთ მოცემულ ფრაგმენტებში ნაჩვენებია, როგორ ვაფართოებთ `Project` მოდელს სტატიკური კონსტრუქტორების დასამატებლად და როგორ ვიყენებთ მათ `Project.swift` ფაილიდან:

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
> **შეთანხმებების დასამყარებელი ინსტრუმენტი**
>
> დააკვირდით, როგორ განვსაზღვრავთ ფუნქციის მეშვეობით შეთანხმებებს სამიზნეების სახელების, ბანდლის იდენტიფიკატორის და საქაღალდეების სტრუქტურის შესახებ.
