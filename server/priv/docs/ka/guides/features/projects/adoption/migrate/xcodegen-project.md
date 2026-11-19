---
{
  "title": "XcodeGen-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები XcodeGen-იდან Tuist-ზე."
}
---
# XcodeGen-პროექტის მიგრაცია {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) არის პროექტების გენერაციის ინსტრუმენტი, რომელიც Xcode-პროექტების აღწერისთვის იყენებს YAML-ს [კონფიგურაციის ფორმატად](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md). ბევრმა ორგანიზაციამ **მიმართა მას, რათა თავიდან აეცილებინა ხშირი Git-კონფლიქტები, რომლებიც Xcode-პროექტებთან მუშაობისას ჩნდება.** თუმცა, ხშირი Git-კონფლიქტები მხოლოდ ერთ-ერთი პრობლემაა, რომელსაც ორგანიზაციები აწყდებიან. Xcode დეველოპერებს უამრავ სირთულესა და არაცხად კონფიგურაციას აჩვენებს, რაც პროექტების მასშტაბური მასშტაბით შენარჩუნებასა და ოპტიმიზაციას ართულებს. XcodeGen ამ მხრივ ბუნებრივად ჩამოუვარდება, რადგან ის არის ინსტრუმენტი, რომელიც ქმნის Xcode-პროექტებს და არა პროექტების მენეჯერი. თუ გჭირდებათ ინსტრუმენტი, რომელიც Xcode-პროექტების გენერაციაზე მეტს გთავაზობთ, განიხილეთ Tuist. Tuist-ის გამოსაყენებლად მიგრაცია არ არის სავალდებულო: [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) ხსნის, რომელი შესაძლებლობები, როგორიცაა Xcode-ქეში და ბილდის ანალიტიკა, მუშაობს XcodeGen-პროექტთან და როდის ღირს მიგრაცია.

> [!TIP]
> **Swift YAML-ის ნაცვლად**
>
> ბევრი ორგანიზაცია Tuist-ს ასევე პროექტების გენერაციის ინსტრუმენტად ამჯობინებს, რადგან ის კონფიგურაციის ფორმატად Swift-ს იყენებს. Swift არის პროგრამირების ენა, რომელიც დეველოპერებისთვის ნაცნობია და მათ Xcode-ის ავტოდამატების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების მოხერხებულობას ანიჭებს.


ქვემოთ მოცემულია რეკომენდაციები და სახელმძღვანელო პრინციპები, რომლებიც დაგეხმარებათ პროექტების XcodeGen-დან Tuist-ზე გადატანაში.

## პროექტების გენერაცია {#project-generation}

როგორც Tuist, ისე XcodeGen გთავაზობთ `generate` ბრძანებას, რომელიც თქვენს პროექტის დეკლარაციას Xcode-პროექტებად და სამუშაო სივრცეებად (workspaces) გარდაქმნის.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

განსხვავება რედაქტირების გამოცდილებაშია. Tuist-ით შეგიძლიათ გაუშვათ `tuist edit` ბრძანება, რომელიც დინამიურად ქმნის Xcode-პროექტს, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ. ეს განსაკუთრებით სასარგებლოა, როდესაც პროექტში სწრაფი ცვლილებების შეტანა გსურთ.

## `project.yaml` {#projectyaml}

XcodeGen-ის `project.yaml` აღწერის ფაილი გარდაიქმნება `Project.swift`-ად. გარდა ამისა, შეგიძლიათ გამოიყენოთ `Workspace.swift`, რათა მოარგოთ, თუ როგორ ჯგუფდება პროექტები სამუშაო სივრცეებში. ასევე შეგიძლიათ გქონდეთ პროექტი `Project.swift` სამიზნეებით (targets), რომლებიც სხვა პროექტების სამიზნეებს მიმართავენ. ასეთ შემთხვევებში, Tuist შექმნის Xcode Workspace-ს, რომელიც ყველა პროექტს მოიცავს.

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
> როგორც XcodeGen, ისე Tuist იზიარებს Xcode-ის ენასა და კონცეფციებს. თუმცა, Tuist-ის Swift-ზე დაფუძნებული კონფიგურაცია გაძლევთ Xcode-ის ავტოდამატების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების მოხერხებულობას.


## სპეციფიკაციის შაბლონები {#spec-templates}

YAML-ის, როგორც პროექტის კონფიგურაციის ენის, ერთ-ერთი ნაკლი იმაში მდგომარეობს, რომ ის ძირითადად არ უზრუნველყოფს ხელახლა გამოყენებადობას YAML-ფაილებს შორის. ეს ხშირი საჭიროებაა პროექტების აღწერისას, რის გადასაჭრელადაც XcodeGen-მა საკუთარი პროპრიეტარული გადაწყვეტა, სახელად *„შაბლონები“*, შეიმუშავა. Tuist-ში ხელახლა გამოყენებადობა ჩაშენებულია თავად ენაში, Swift-ში, და Swift-მოდულის სახით, სახელად <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>, რომელიც საშუალებას გაძლევთ კოდი ყველა მანიფესტის ფაილში ხელახლა გამოიყენოთ.

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
