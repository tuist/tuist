---
{
  "title": "XcodeGen პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები XcodeGen-დან Tuist-ში."
}
---
# XcodeGen-ის პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც Xcode-ის პროექტების აღწერისთვის იყენებს YAML-ს, როგორც [კონფიგურაციის ფორმატს](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). ბევრმა ორგანიზაციამ **მიმართა მას, რათა თავიდან აეცილებინა ხშირი Git-კონფლიქტები, რომლებიც Xcode-ის პროექტებთან მუშაობისას ჩნდება.** თუმცა, ხშირი Git-კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და იმპლიციტურ კონფიგურაციას უჩენს, რაც პროექტების მასშტაბურად შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ ბუნებრივად ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-ის პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც დაგეხმარებათ Xcode-ის პროექტების გენერაციის მიღმა, განიხილეთ Tuist. Tuist-ის გამოყენებისთვის მიგრაცია არ არის სავალდებულო: [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) ხსნის, თუ რომელი შესაძლებლობები, მაგალითად Xcode-ის ქეში და ბილდის ანალიტიკა, მუშაობს XcodeGen-ის პროექტთან და როდის ღირს მიგრაცია.

> [!TIP]
> **Swift YAML-ის ნაცვლად**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე ამჯობინებს პროექტების გენერაციის ინსტრუმენტად, რადგან ის კონფიგურაციის ფორმატად Swift-ს იყენებს. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ცნობილია და მათ საშუალებას აძლევს ისარგებლონ Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის შესაძლებლობებით.


ქვემოთ მოცემულია რჩევები და გაიდლაინები, რომლებიც დაგეხმარებათ პროექტების XcodeGen-იდან Tuist-ზე მიგრაციაში.

## პროექტის გენერაცია {#project-generation}

როგორც Tuist, ასევე XcodeGen გთავაზობთ `generate` ბრძანებას, რომელიც თქვენს პროექტის დეკლარაციას Xcode-ის პროექტებად და სამუშაო სივრცეებად (workspaces) გარდაქმნის.

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

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად. ასევე, შეგიძლიათ გამოიყენოთ `Workspace.swift` სამუშაო სივრცეებში პროექტების დაჯგუფების პერსონალიზაციისთვის. შეგიძლიათ ასევე გქონდეთ პროექტი `Project.swift` თარგეტებით, რომლებიც სხვა პროექტების თარგეტებს მიმართავენ. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

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
> როგორც XcodeGen, ასევე Tuist იყენებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ საშუალებას ისარგებლოთ Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის შესაძლებლობებით.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი იმაში მდგომარეობს, რომ ის „ყუთიდან“ არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML-ფაილებს შორის. ეს ხშირი საჭიროებაა პროექტების აღწერისას, რის გადასაჭრელადაც XcodeGen-მა საკუთარი პროპრიეტარული გადაწყვეტა, სახელად *„შაბლონები“*, შეიმუშავა. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეებში</.localized_link> Swift-მოდულის საშუალებით, რაც საშუალებას გაძლევთ კოდი ხელახლა გამოიყენოთ ყველა თქვენს მანიფესტ ფაილში.

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
