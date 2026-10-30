---
{
  "title": "XcodeGen-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · ადაპტაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები XcodeGen-დან Tuist-ზე."
}
---
# XcodeGen-ის პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც Xcode-ის პროექტების აღწერისთვის იყენებს YAML-ს, როგორც [კონფიგურაციის ფორმატს](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). ბევრმა ორგანიზაციამ **აირჩია ის, რათა თავიდან აერიდებინა Git-ის ხშირი კონფლიქტები, რომლებიც Xcode-ის პროექტებთან მუშაობისას ჩნდება.** თუმცა, Git-ის ხშირი კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და იმპლიციტურ კონფიგურაციას აწვდის, რაც პროექტების მასშტაბურად შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ დიზაინით ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-ის პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც დაგეხმარებათ Xcode-ის პროექტების გენერაციის მიღმა, შეგიძლიათ განიხილოთ Tuist.

> [!TIP]
> **Swift YAML-ზე**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე ამჯობინებს პროექტების გენერაციის ინსტრუმენტად, რადგან ის კონფიგურაციის ფორმატად Swift-ს იყენებს. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ნაცნობია და რომელიც მათ აძლევს Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების მოხერხებულობას.


ქვემოთ მოცემულია ზოგიერთი მოსაზრება და სახელმძღვანელო პრინციპი, რომლებიც დაგეხმარებათ პროექტების XcodeGen-დან Tuist-ზე გადატანაში.

## პროექტების გენერაცია {#project-generation}

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

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად. გარდა ამისა, შეგიძლიათ გამოიყენოთ `Workspace.swift`, რათა მოარგოთ, თუ როგორ ჯგუფდება პროექტები სამუშაო სივრცეებში. ასევე შეგიძლიათ გქონდეთ პროექტი `Project.swift`, რომლის მიზნებიც (targets) მიუთითებენ სხვა პროექტების მიზნებზე. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

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
> როგორც XcodeGen, ისე Tuist იყენებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების მოხერხებულობას.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი იმაშია, რომ ის ძირითადად არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML ფაილებს შორის. ეს ხშირი საჭიროებაა პროექტების აღწერისას, რაც XcodeGen-მა თავისი საკუთარი პროპრიეტარული გადაწყვეტილებით, სახელწოდებით *„შაბლონები“*, უნდა გადაეჭრა. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და Swift-ის მოდულის სახით, რომელსაც ეწოდება <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link>, რაც საშუალებას გაძლევთ ხელახლა გამოიყენოთ კოდი თქვენს ყველა მანიფესტ ფაილში.

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
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
