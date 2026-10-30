---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ შექმნათ და გამოიყენოთ პლაგინები Tuist-ში მისი ფუნქციონალის გასაფართოებლად."
}
---
# პლაგინები {#plugins}

პლაგინები არის ინსტრუმენტი Tuist-ის არტეფაქტების გასაზიარებლად და ხელახლა გამოსაყენებლად რამდენიმე პროექტში. მხარდაჭერილია შემდეგი არტეფაქტები:

- <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link> რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/templates">შაბლონები</.localized_link> რამდენიმე პროექტში.
- ამოცანები რამდენიმე პროექტში.
- <.localized_link href="/guides/features/projects/synthesized-files">რესურსებზე წვდომის ობიექტების</.localized_link> შაბლონი რამდენიმე პროექტში

გაითვალისწინეთ, რომ პლაგინები შექმნილია Tuist-ის ფუნქციონალის გასაფართოებლად მარტივი გზით. ამიტომ, არსებობს **გარკვეული შეზღუდვები**:

- პლაგინი ვერ იქნება დამოკიდებული სხვა პლაგინზე.
- პლაგინი ვერ იქნება დამოკიდებული მესამე მხარის Swift პაკეტებზე
- პლაგინი ვერ გამოიყენებს პროექტის აღწერის დამხმარეებს იმ პროექტიდან, რომელიც იყენებს პლაგინს.

თუ მეტი მოქნილობა გჭირდებათ, განიხილეთ ინსტრუმენტისთვის ფუნქციის შეთავაზება ან საკუთარი გადაწყვეტის აგება Tuist-ის გენერაციის ჩარჩოზე, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## პლაგინების ტიპები {#plugin-types}

### პროექტის აღწერის დამხმარე პლაგინი {#project-description-helper-plugin}

პროექტის აღწერის დამხმარე პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, სადაც განაცხადებულია პლაგინის სახელი, და `ProjectDescriptionHelpers` დირექტორიას, რომელიც შეიცავს დამხმარე Swift ფაილებს.

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

### რესურსებზე წვდომის ობიექტების შაბლონების პლაგინი {#resource-accessor-templates-plugin}

თუ გჭირდებათ <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">სინთეზირებული რესურსებზე წვდომის ობიექტების</.localized_link> გაზიარება, შეგიძლიათ გამოიყენოთ ამ ტიპის პლაგინი. პლაგინი წარმოდგენილია დირექტორიით, რომელიც შეიცავს `Plugin.swift` მანიფესტის ფაილს, სადაც განაცხადებულია პლაგინის სახელი, და `ResourceSynthesizers` დირექტორიას, რომელიც შეიცავს რესურსებზე წვდომის ობიექტების შაბლონის ფაილებს.


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

როდესაც პროექტში განსაზღვრავთ რესურსების სინთეზატორებს, შეგიძლიათ მიუთითოთ პლაგინის სახელი პლაგინიდან შაბლონების გამოსაყენებლად:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### ამოცანის პლაგინი <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **მოძველებულია**
>
> ამოცანის პლაგინები მოძველებულია. თუ პროექტისთვის ავტომატიზაციის გადაწყვეტას ეძებთ, იხილეთ [ეს ბლოგ-პოსტი](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).


ამოცანები არის `$PATH`-ში ხელმისაწვდომი შესრულებადი ფაილები, რომლებიც გამოძახებადი არიან `tuist` ბრძანების მეშვეობით, თუ ისინიც ემორჩილებიან სახელდების კონვენციას `tuist-<task-name>`. ადრეულ ვერსიებში Tuist გთავაზობდა რამდენიმე სუსტ კონვენციას და ინსტრუმენტს `tuist plugin`-ის ქვეშ `build`, `run`, `test` და `archive` ამოცანებისთვის, რომლებიც წარმოდგენილი იყო Swift Packages-ში შესრულებადი ფაილებით, მაგრამ ჩვენ ეს ფუნქცია მოვაძველეთ, რადგან ის ზრდის ინსტრუმენტის მხარდაჭერის ტვირთსა და სირთულეს.

თუ Tuist-ს იყენებდით ამოცანების გასავრცელებლად, გირჩევთ ააწყოთ თქვენი
- შეგიძლიათ განაგრძოთ `ProjectAutomation.xcframework`-ის გამოყენება, რომელიც ვრცელდება Tuist-ის ყოველ გამოცემასთან ერთად, რათა თქვენს ლოგიკაში `let graph = try Tuist.graph()`-ის მეშვეობით მიიღოთ წვდომა პროექტის გრაფზე. ბრძანება იყენებს სისტემურ პროცესს `tuist` ბრძანების გასაშვებად და აბრუნებს პროექტის გრაფის მეხსიერებაში არსებულ წარმოდგენას.
- ამოცანების გასავრცელებლად გირჩევთ GitHub-ის გამოცემებში ჩართოთ fat binary, რომელიც მხარს უჭერს `arm64`-ს და `x86_64`-ს, და გამოიყენოთ [Mise](https://mise.jdx.dev) როგორც ინსტალაციის ინსტრუმენტი. იმისთვის, რომ Mise-ს ასწავლოთ თქვენი ინსტრუმენტის ინსტალაცია, დაგჭირდებათ პლაგინების რეპოზიტორი. შეგიძლიათ გამოიყენოთ [Tuist-ის](https://github.com/asdf-community/asdf-tuist) რეპოზიტორი როგორც ნიმუში.
- თუ თქვენს ინსტრუმენტს დაარქმევთ `tuist-{xxx}` და მომხმარებლებს შეეძლებათ მისი ინსტალაცია `mise install`-ის გაშვებით, მათ შეეძლებათ მისი გაშვება ან პირდაპირი გამოძახებით, ან `tuist xxx`-ის მეშვეობით.

> [!NOTE]
> **ProjectAutomation-ის მომავალი**
>
> ჩვენ ვგეგმავთ `ProjectAutomation`-ის და `XcodeGraph`-ის მოდელების კონსოლიდაციას ერთ უკუთავსებად თავსებად ფრეიმვორკად, რომელიც მომხმარებელს სრულად უჩვენებს პროექტის გრაფს. გარდა ამისა, გენერაციის ლოგიკას გამოვყოფთ ახალ შრედ, `XcodeGraph`, რომლის გამოყენებაც თქვენს საკუთარ CLI-დანაც შეგეძლებათ. წარმოიდგინეთ ეს როგორც თქვენი საკუთარი Tuist-ის აგება.


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

თუ გსურთ პლაგინის ხელახლა გამოყენება სხვადასხვა რეპოზიტორიაში მყოფ პროექტებში, შეგიძლიათ ატვირთოთ თქვენი პლაგინი Git რეპოზიტორიაში და მიუთითოთ იგი `Tuist.swift` ფაილში:

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
> **ვერსიების ამოხსნა არ ხდება**
>
> როგორც შეამჩნიეთ, ჩვენ არ ვუზრუნველყოფთ პლაგინების ვერსიების ამოხსნას. გირჩევთ გამოიყენოთ Git-ის ტეგები ან SHA-ები აღწარმოებადობის უზრუნველსაყოფად.


> [!TIP]
> **პროექტის აღწერის დამხმარე პლაგინები**
>
> როდესაც იყენებთ პროექტის აღწერის დამხმარე პლაგინს, დამხმარეების შემცველი მოდულის სახელი ემთხვევა პლაგინის სახელს
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
