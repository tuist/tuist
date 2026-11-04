---
{
  "title": "XcodeGen-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადავიტანოთ თქვენი პროექტები XcodeGen-დან Tuist-ზე."
}
---
# XcodeGen-ის პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც Xcode-ის პროექტების აღწერისთვის იყენებს YAML-ს, როგორც [კონფიგურაციის ფორმატს](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). ბევრმა ორგანიზაციამ **მიმართა მას, რათა თავი დაეღწია Xcode-ის პროექტებთან მუშაობისას ხშირად წარმოქმნილი Git-კონფლიქტებისგან.** თუმცა, ხშირი Git-კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და იმპლიციტურ კონფიგურაციას უჩვენებს, რაც პროექტების მასშტაბურად შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ დიზაინით ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-ის პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც Xcode-ის პროექტების გენერაციის მიღმა დაგეხმარებათ, შესაძლოა, Tuist განიხილოთ.

> [!TIP]
> **Swift YAML-ზე**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე პროექტების გენერაციის ინსტრუმენტად ამჯობინებს, რადგან ის კონფიგურაციის ფორმატად Swift-ს იყენებს. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ნაცნობია და მათ საშუალებას აძლევს გამოიყენონ Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციები.


ქვემოთ მოცემულია რჩევები და სახელმძღვანელო პრინციპები, რომლებიც დაგეხმარებათ პროექტების XcodeGen-დან Tuist-ზე გადატანაში.

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

განსხვავება რედაქტირების გამოცდილებაშია. Tuist-ით შეგიძლიათ გაუშვათ `tuist edit` ბრძანება, რომელიც დინამიურად ქმნის Xcode-ის პროექტს, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ. ეს განსაკუთრებით სასარგებლოა, როდესაც პროექტში სწრაფი ცვლილებების შეტანა გსურთ.

## `project.yaml` {#projectyaml}

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად.此外, შეგიძლიათ გამოიყენოთ `Workspace.swift`, რათა მოარგოთ, თუ როგორ ჯგუფდებიან პროექტები სამუშაო სივრცეებში. ასევე შეგიძლიათ გქონდეთ პროექტი `Project.swift` მიზნებით (targets), რომლებიც სხვა პროექტების მიზნებს მიმართავენ. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

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
> როგორც XcodeGen, ასევე Tuist იყენებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ საშუალებას, გამოიყენოთ Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციები.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი იმაში მდგომარეობს, რომ ის „ყუთიდან“ არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML ფაილებს შორის. ეს ხშირი საჭიროებაა პროექტების აღწერისას, რაც XcodeGen-მა საკუთარი პროპრიეტარული გადაწყვეტით, სახელწოდებით *„შაბლონები“*, უნდა გადაეჭრა. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეების</.localized_link> სახელწოდების Swift მოდულის მეშვეობით, რაც საშუალებას გაძლევთ, ხელახლა გამოიყენოთ კოდი თქვენს ყველა მანიფესტ ფაილში.

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
