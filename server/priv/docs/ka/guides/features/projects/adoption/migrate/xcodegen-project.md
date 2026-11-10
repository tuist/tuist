---
{
  "title": "XcodeGen პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები XcodeGen-დან Tuist-ზე."
}
---
# XcodeGen-ის პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც Xcode-ის პროექტების აღსაწერად იყენებს YAML-ს [კონფიგურაციის ფორმატად](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). ბევრმა ორგანიზაციამ **მიმართა მას, რათა თავი დაეღწია Git-ში ხშირი კონფლიქტებისგან, რომლებიც Xcode-ის პროექტებთან მუშაობისას ჩნდება.** თუმცა, Git-ში ხშირი კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და იმპლიციტურ კონფიგურაციას უჩენს, რაც პროექტების მასშტაბურად შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ ბუნებრივად ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-ის პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც დაგეხმარებათ Xcode-ის პროექტების გენერაციის მიღმა, შეგიძლიათ განიხილოთ Tuist.

> [!TIP]
> **Swift YAML-ის ნაცვლად**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე ამჯობინებს პროექტების გენერაციის ინსტრუმენტად, რადგან ის კონფიგურაციის ფორმატად Swift-ს იყენებს. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ნაცნობია და რომელიც მათ საშუალებას აძლევს ისარგებლონ Xcode-ის ავტოდამატებით, ტიპების შემოწმებითა და ვალიდაციის ფუნქციებით.


ქვემოთ მოცემულია ზოგიერთი მოსაზრება და რეკომენდაცია, რომელიც დაგეხმარებათ პროექტების XcodeGen-დან Tuist-ზე გადატანაში.

## პროექტების გენერაცია {#project-generation}

როგორც Tuist, ისე XcodeGen უზრუნველყოფს `generate` ბრძანებას, რომელიც თქვენს პროექტის დეკლარაციას Xcode-ის პროექტებად და სამუშაო სივრცეებად (workspaces) აქცევს.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

განსხვავება რედაქტირების გამოცდილებაშია. Tuist-ით შეგიძლიათ გაუშვათ `tuist edit` ბრძანება, რომელიც დინამიურად ქმნის Xcode-ის პროექტს, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ. ეს განსაკუთრებით სასარგებლოა, როცა პროექტში სწრაფი ცვლილებების შეტანა გსურთ.

## `project.yaml` {#projectyaml}

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად. გარდა ამისა, შეგიძლიათ გამოიყენოთ `Workspace.swift`, რათა მოარგოთ, თუ როგორ ჯგუფდება პროექტები სამუშაო სივრცეებში. ასევე შეგიძლიათ გქონდეთ პროექტის `Project.swift` ფაილი სამიზნეებით (targets), რომლებიც სხვა პროექტების სამიზნეებს მიმართავენ. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

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
> როგორც XcodeGen, ისე Tuist იყენებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ საშუალებას ისარგებლოთ Xcode-ის ავტოდამატებით, ტიპების შემოწმებითა და ვალიდაციის ფუნქციებით.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი ის არის, რომ ის ძირითადად არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML ფაილებს შორის. ეს ხშირად საჭიროა პროექტების აღწერისას, რაც XcodeGen-მა თავისი პროპრიეტარული გადაწყვეტით, ე.წ. *„შაბლონებით“*, უნდა გადაეწყვიტა. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და Swift-ის მოდულის სახით, რომელსაც <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link> ეწოდება და რომელიც საშუალებას გაძლევთ კოდი ხელახლა გამოიყენოთ ყველა თქვენს მანიფესტ ფაილში.

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
