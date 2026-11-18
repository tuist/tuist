---
{
  "title": "XcodeGen-პროექტის გადატანა",
  "titleTemplate": ":title · გადატანა · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები XcodeGen-დან Tuist-ზე."
}
---
# XcodeGen-ის პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც იყენებს YAML-ს [კონფიგურაციის ფორმატად](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) Xcode-ის პროექტების აღწერისთვის. ბევრი ორგანიზაცია **აირჩია ის, რათა თავი დაეღწია Git-ის ხშირი კონფლიქტებისგან, რომლებიც ჩნდება Xcode-ის პროექტებზე მუშაობისას.** თუმცა, Git-ის ხშირი კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და იმპლიციტურ კონფიგურაციას უჩენს, რაც პროექტების მასშტაბურ დონეზე შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ დიზაინითვე ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-ის პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც დაგეხმარებათ Xcode-ის პროექტების გენერაციის მიღმა, შესაძლოა Tuist განიხილოთ. Tuist-ის გამოყენებისთვის მიგრაცია სავალდებულო არ არის: [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) ხსნის, თუ რომელი შესაძლებლობები, როგორიცაა Xcode-ის ქეში და ბილდის ანალიტიკა, მუშაობს XcodeGen-ის პროექტთან და როდის ღირს მიგრაცია.

> [!TIP]
> **Swift YAML-ის ნაცვლად**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე ამჯობინებს პროექტების გენერაციის ინსტრუმენტად, რადგან ის იყენებს Swift-ს კონფიგურაციის ფორმატად. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ცნობილია და რომელიც მათ საშუალებას აძლევს ისარგებლონ Xcode-ის ავტოდამატების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციებით.


ქვემოთ მოცემულია რეკომენდაციები და გაიდლაინები, რომლებიც დაგეხმარებათ თქვენი პროექტების XcodeGen-დან Tuist-ზე გადატანაში.

## პროექტის გენერაცია {#project-generation}

როგორც Tuist, ისე XcodeGen უზრუნველყოფს `generate` ბრძანებას, რომელიც თქვენს პროექტის დეკლარაციას Xcode-ის პროექტებად და სამუშაო სივრცეებად (workspaces) გარდაქმნის.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

განსხვავება რედაქტირების გამოცდილებაშია. Tuist-ით შეგიძლიათ გაუშვათ `tuist edit` ბრძანება, რომელიც დინამიურად ქმნის Xcode-ის პროექტს, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ. ეს განსაკუთრებით სასარგებლოა, როდესაც პროექტში სწრაფი ცვლილებების შეტანა გსურთ.

## `project.yaml` {#projectyaml}

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად. გარდა ამისა, შეგიძლიათ გამოიყენოთ `Workspace.swift`, რათა მოარგოთ, თუ როგორ ჯგუფდება პროექტები სამუშაო სივრცეებში. ასევე შეგიძლიათ გქონდეთ პროექტი `Project.swift` ტარგეტებით, რომლებიც მიმართავენ სხვა პროექტების ტარგეტებს. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

> [!TIP]
> **Xcode-ის ენა**
>
> როგორც XcodeGen, ისე Tuist იყენებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ საშუალებას ისარგებლოთ Xcode-ის ავტოდამატების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციებით.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი იმაში მდგომარეობს, რომ ის „ყუთიდან“ არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML ფაილებს შორის. ეს ხშირი საჭიროებაა პროექტების აღწერისას, რის გადასაჭრელადაც XcodeGen-მა შეიმუშავა საკუთარი პროპრიეტარული გადაწყვეტა სახელწოდებით *„შაბლონები“*. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და Swift-ის მოდულის საშუალებით, რომელსაც ეწოდება <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link>, რაც საშუალებას გაძლევთ ხელახლა გამოიყენოთ კოდი ყველა თქვენს მანიფესტ ფაილში.

::: code-group
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature"))
```
:::
