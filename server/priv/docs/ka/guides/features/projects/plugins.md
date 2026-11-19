---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ შექმნათ და გამოიყენოთ პლაგინები Tuist-ში მისი ფუნქციონალის გასაფართოებლად."
}
---
# პლაგინები {#plugins}

პლაგინები არის ინსტრუმენტი Tuist-ის არტეფაქტების გასაზიარებლად და ხელახლა გამოსაყენებლად რამდენიმე პროექტში. მხარდაჭერილია შემდეგი არტეფაქტები:

- <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link> რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/templates">შაბლონები</.localized_link> რამდენიმე პროექტში.
- ამოცანები რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/synthesized-files">რესურსების წვდომის</.localized_link> შაბლონი რამდენიმე პროექტში

გაითვალისწინეთ, რომ პლაგინები შექმნილია Tuist-ის ფუნქციონალის გასაფართოებლად მარტივი გზით. შესაბამისად, არსებობს **ზოგიერთი შეზღუდვა, რომელიც უნდა გაითვალისწინოთ**:

- პლაგინს არ შეუძლია იყოს დამოკიდებული სხვა პლაგინზე.
- პლაგინს არ შეუძლია იყოს დამოკიდებული მესამე მხარის Swift პაკეტებზე
- პლაგინს არ შეუძლია გამოიყენოს პროექტის აღწერის დამხმარეები იმ პროექტიდან, რომელიც იყენებს პლაგინს.

თუ მეტი მოქნილობა გჭირდებათ, განიხილეთ ინსტრუმენტისთვის ფუნქციის შეთავაზება ან საკუთარი გადაწყვეტის აგება Tuist-ის გენერაციის ჩარჩოზე, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator).

## პლაგინის ტიპები {#plugin-types}

### პროექტის აღწერის დამხმარე პლაგინი {#project-description-helper-plugin}

პროექტის აღწერის დამხმარე პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, რომელიც აცხადებს პლაგინის სახელს, და `ProjectDescriptionHelpers` დირექტორიას, რომელიც შეიცავს დამხმარე Swift ფაილებს.

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

### რესურსების წვდომის შაბლონების პლაგინი {#resource-accessor-templates-plugin}

თუ გჭირდებათ <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">სინთეზირებული რესურსების წვდომის</.localized_link> გაზიარება, შეგიძლიათ გამოიყენოთ ამ ტიპის პლაგინი. პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, რომელიც აცხადებს პლაგინის სახელს, და `ResourceSynthesizers` დირექტორიას, რომელიც შეიცავს რესურსების წვდომის შაბლონის ფაილებს.


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

როდესაც პროექტში განსაზღვრავთ რესურსების სინთეზატორებს, შეგიძლიათ მიუთითოთ პლაგინის სახელი პლაგინიდან შაბლონების გამოყენებისთვის:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### ამოცანის პლაგინი <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **მოძველებული**
>
> ამოცანის პლაგინები მოძველებულია. თუ თქვენს პროექტს ავტომატიზაციის გადაწყვეტას ეძებთ, იხილეთ [ეს ბლოგ-პოსტი](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).


ამოცანები არის `$PATH`-ში ხელმისაწვდომი შესრულებადი ფაილები, რომლებიც გამოძახებადი არიან `tuist` ბრძანებით, თუ ისინიც იცავენ სახელდების კონვენციას `tuist-<task-name>`. ადრეულ ვერსიებში Tuist უზრუნველყოფდა ზოგიერთ სუსტ კონვენციას და ინსტრუმენტებს `tuist plugin` ქვეშ `build`, `run`, `test` და `archive` ამოცანებისთვის, რომლებიც წარმოდგენილი იყვნენ Swift Packages-ში შესრულებადი ფაილებით, მაგრამ ჩვენ ეს ფუნქცია მოვაძველეთ, რადგან ის ზრდის ინსტრუმენტის შენარჩუნების ტვირთსა და სირთულეს.

თუ ამოცანებს პლაგინების სახით ავრცელებდით, ნაცვლად ამისა ააწყეთ ისინი როგორც დამოუკიდებელი შესრულებადი ფაილები:

- შეგიძლიათ განაგრძოთ `ProjectAutomation.xcframework`-ის გამოყენება, რომელიც ყოველ Tuist გამოცემასთან ერთად ვრცელდება, რათა თქვენი ლოგიკიდან მიიღოთ წვდომა პროექტის გრაფზე `let graph = try Tuist.graph()`-ის მეშვეობით. ის ასრულებს `tuist`-ს როგორც შვილობილ პროცესს და აბრუნებს პროექტის გრაფის წარმოდგენას მეხსიერებაში.
- ამოცანების გავრცელებისთვის, ჩვენ გირჩევთ GitHub-ის გამოცემებში გამოაქვეყნოთ უნივერსალური ბინარი, რომელიც მხარდაჭერილია `arm64` და `x86_64` არქიტექტურებისთვის, და გამოიყენოთ [Mise](https://mise.jdx.dev) როგორც ინსტალაციის ინსტრუმენტი. იმისთვის, რომ Mise-ს მიანიჭოთ ინსტრუქცია თქვენი ინსტრუმენტის ინსტალაციის შესახებ, დაგჭირდებათ პლაგინის რეპოზიტორი. შეგიძლიათ გამოიყენოთ [Tuist-ის](https://github.com/asdf-community/asdf-tuist) რეპოზიტორი როგორც მაგალითი.
- თუ თქვენს ინსტრუმენტს დაარქმევთ `tuist-{xxx}` და მომხმარებლებს შეეძლებათ მისი ინსტალაცია `mise install`-ის გაშვებით, მათ შეეძლებათ მისი გაშვება ან პირდაპირი გამოძახებით, ან `tuist xxx`-ის მეშვეობით.

> [!NOTE]
> **ProjectAutomation-ის მომავალი**
>
> ჩვენ ვგეგმავთ `ProjectAutomation` და `XcodeGraph` მოდელების გაერთიანებას ერთ უკუთავსებად ჩარჩოში, რომელიც მომხმარებელს სრულად უჩვენებს პროექტის გრაფს. გარდა ამისა, ჩვენ გამოვყოფთ გენერაციის ლოგიკას ახალ შრედ, `XcodeGraph`, რომლის გამოყენებაც თქვენს საკუთარ CLI-შიც შეგეძლებათ. წარმოიდგინეთ ეს როგორც საკუთარი Tuist-ის აგება.


## პლაგინების გამოყენება {#using-plugins}

პლაგინის გამოსაყენებლად, თქვენ უნდა დაამატოთ ის თქვენი პროექტის [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) მანიფესტის ფაილში:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

თუ გსურთ პლაგინის ხელახლა გამოყენება სხვადასხვა რეპოზიტორიაში მყოფ პროექტებში, შეგიძლიათ ატვირთოთ თქვენი პლაგინი Git რეპოზიტორიაში და მიუთითოთ ის `Tuist.swift` ფაილში:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

პლაგინების დამატების შემდეგ, `tuist install` ჩამოტვირთავს პლაგინებს გლობალურ ქეშის დირექტორიაში.

> [!NOTE]
> **ვერსიების გადაწყვეტა არ ხდება**
>
> როგორც შენიშნეთ, ჩვენ არ ვუზრუნველყოფთ პლაგინების ვერსიების გადაწყვეტას. ჩვენ გირჩევთ Git ტეგების ან SHA-ების გამოყენებას აღწარმოებადობის უზრუნველსაყოფად.


> [!TIP]
> **პროექტის აღწერის დამხმარე პლაგინები**
>
> როდესაც იყენებთ პროექტის აღწერის დამხმარე პლაგინს, მოდულის სახელი, რომელიც შეიცავს დამხმარეებს, არის პლაგინის სახელი
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
