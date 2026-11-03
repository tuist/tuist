---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ და გამოიყენოთ პლაგინები Tuist-ში მისი ფუნქციონალის გასაფართოებლად."
}
---
# პლაგინები {#plugins}

პლაგინები არის ინსტრუმენტი Tuist-ის არტეფაქტების გასაზიარებლად და ხელახლა გამოსაყენებლად რამდენიმე პროექტში. მხარდაჭერილია შემდეგი არტეფაქტები:

- <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link> რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/templates">შაბლონები</.localized_link> რამდენიმე პროექტში.
- ამოცანები რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/synthesized-files">რესურსების წვდომის კოდის გენერატორის</.localized_link> შაბლონი რამდენიმე პროექტში

გაითვალისწინეთ, რომ პლაგინები შექმნილია Tuist-ის ფუნქციონალის გასაფართოებლად მარტივი გზით. ამიტომ, არსებობს **გარკვეული შეზღუდვები, რომლებიც უნდა გაითვალისწინოთ**:

- პლაგინს არ შეუძლია იყოს დამოკიდებული სხვა პლაგინზე.
- პლაგინს არ შეუძლია იყოს დამოკიდებული მესამე მხარის Swift პაკეტებზე
- პლაგინს არ შეუძლია გამოიყენოს პროექტის აღწერის დამხმარე საშუალებები იმ პროექტიდან, რომელიც იყენებს პლაგინს.

თუ მეტი მოქნილობა გჭირდებათ, განიხილეთ ინსტრუმენტისთვის ფუნქციის შეთავაზება ან თქვენი საკუთარი გადაწყვეტის აგება Tuist-ის გენერაციის ჩარჩოზე, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## პლაგინების ტიპები {#plugin-types}

### პროექტის აღწერის დამხმარე პლაგინი {#project-description-helper-plugin}

პროექტის აღწერის დამხმარე პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, სადაც განსაზღვრულია პლაგინის სახელი, და `ProjectDescriptionHelpers` დირექტორიას, რომელიც შეიცავს დამხმარე Swift ფაილებს.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### რესურსების წვდომის კოდის გენერატორის შაბლონების პლაგინი {#resource-accessor-templates-plugin}

თუ გჭირდებათ <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">სინთეზირებული რესურსების წვდომის კოდის გენერატორების</.localized_link> გაზიარება, შეგიძლიათ გამოიყენოთ ამ ტიპის პლაგინი. პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, სადაც განსაზღვრულია პლაგინის სახელი, და `ResourceSynthesizers` დირექტორიას, რომელიც შეიცავს რესურსების წვდომის კოდის გენერატორის შაბლონის ფაილებს.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

შაბლონის სახელი არის რესურსის ტიპის [camel case](https://en.wikipedia.org/wiki/Camel_case) ვერსია:

| რესურსის ტიპი | შაბლონის ფაილის სახელი |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

როდესაც პროექტში განსაზღვრავთ რესურსების სინთეზატორებს, შეგიძლიათ მიუთითოთ პლაგინის სახელი, რათა გამოიყენოთ შაბლონები პლაგინიდან:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### ამოცანის პლაგინი <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **მოძველებულია**
>
> ამოცანის პლაგინები მოძველებულია. თუ თქვენს პროექტს ავტომატიზაციის გადაწყვეტას ეძებთ, იხილეთ [ეს ბლოგ-პოსტი](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).


ამოცანები არის `$PATH`-ში ხელმისაწვდომი შესრულებადი ფაილები, რომლებიც გამოიძახება `tuist` ბრძანების მეშვეობით, თუ ისინიც იცავენ სახელდების კონვენციას `tuist-<task-name>`. Tuist-ის ადრეულ ვერსიებში `tuist plugin` ქვეშ წარმოდგენილი იყო ზოგიერთი სუსტი კონვენცია და ინსტრუმენტები Swift პაკეტებში შესრულებადი ფაილებით წარმოდგენილი `build`, `run`, `test` და `archive` ამოცანებისთვის, მაგრამ ჩვენ ეს ფუნქცია მოვაძველეთ, რადგან ის ზრდის ინსტრუმენტის შენარჩუნების ტვირთს და სირთულეს.

თუ Tuist-ს იყენებდით ამოცანების გავრცელებისთვის, გირჩევთ ააწყოთ თქვენი
- შეგიძლიათ განაგრძოთ `ProjectAutomation.xcframework`-ის გამოყენება, რომელიც ყოველ Tuist რელიზთან ერთად ვრცელდება, რათა თქვენს ლოგიკაში `let graph = try Tuist.graph()`-ის მეშვეობით მიიღოთ წვდომა პროექტის გრაფზე. ბრძანება იყენებს სისტემურ პროცესს `tuist` ბრძანების გასაშვებად და აბრუნებს პროექტის გრაფის წარმოდგენას მეხსიერებაში.
- ამოცანების გავრცელებისთვის გირჩევთ GitHub რელიზებში ჩართოთ fat ბინარი, რომელიც მხარდაჭერილია `arm64` და `x86_64` არქიტექტურებისთვის, და გამოიყენოთ [Mise](https://mise.jdx.dev) როგორც ინსტალაციის ინსტრუმენტი. Mise-ისთვის იმის მისათითებლად, თუ როგორ უნდა დაინსტალირდეს თქვენი ინსტრუმენტი, დაგჭირდებათ პლაგინის რეპოზიტორი. შეგიძლიათ გამოიყენოთ [Tuist-ის](https://github.com/asdf-community/asdf-tuist) რეპოზიტორი როგორც ნიმუში.
- თუ თქვენს ინსტრუმენტს დაარქმევთ `tuist-{xxx}` და მომხმარებლებს შეეძლებათ მისი ინსტალაცია `mise install`-ის გაშვებით, მათ შეეძლებათ მისი გაშვება ან პირდაპირი გამოძახებით, ან `tuist xxx`-ის მეშვეობით.

> [!NOTE]
> **ProjectAutomation-ის მომავალი**
>
> ჩვენ ვგეგმავთ `ProjectAutomation` და `XcodeGraph` მოდელების კონსოლიდაციას ერთ უკუთავსებად ფრეიმვორკში, რომელიც მომხმარებელს პროექტის გრაფის სრულად ხელმისაწვდომს გახდის. გარდა ამისა, გენერაციის ლოგიკას გამოვყოფთ ახალ შრეში, `XcodeGraph`, რომლის გამოყენებაც თქვენს საკუთარ CLI-დანაც შეგიძლიათ. წარმოიდგინეთ ეს, როგორც თქვენი საკუთარი Tuist-ის აგება.


## პლაგინების გამოყენება {#using-plugins}

პლაგინის გამოსაყენებლად, ის უნდა დაამატოთ თქვენი პროექტის [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) მანიფესტის ფაილში:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

თუ გსურთ პლაგინის ხელახლა გამოყენება სხვადასხვა რეპოზიტორიაში მყოფ პროექტებში, შეგიძლიათ პლაგინი Git რეპოზიტორიაში განათავსოთ და მიუთითოთ ის `Tuist.swift` ფაილში:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

პლაგინების დამატების შემდეგ, `tuist install` ჩამოტვირთავს პლაგინებს გლობალური ქეშის დირექტორიაში.

> [!NOTE]
> **ვერსიების რეზოლუციის არარსებობა**
>
> როგორც შეამჩნიეთ, ჩვენ არ ვუზრუნველყოფთ პლაგინების ვერსიების რეზოლუციას. გირჩევთ გამოიყენოთ Git ტეგები ან SHA-ები აღწარმოებადობის უზრუნველსაყოფად.


> [!TIP]
> **პროექტის აღწერის დამხმარე პლაგინები**
>
> როდესაც იყენებთ პროექტის აღწერის დამხმარე პლაგინს, დამხმარეების შემცველი მოდულის სახელი ემთხვევა პლაგინის სახელს.
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
