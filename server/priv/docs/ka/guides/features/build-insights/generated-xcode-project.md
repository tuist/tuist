---
{
  "title": "Xcode-ის გენერირებული პროექტი",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist-ით გენერირებული Xcode-ის პროექტის ბილდის ანალიტიკის თვალყურის დევნება Tuist-ის დაფაზე."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-build-insights}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავენ `tuist inspect build` post-action-ს.

>
> თუ არ გსურთ ბილდის ინსაიტების თრეკინგი გენერირებულ სქემებში, გათიშეთ ის [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)-ის გამოყენებით.

თუ იყენებთ გენერირებულ პროექტებს მორგებული სქემებით, თავად უნდა დაამატოთ post-action. [Mise](https://mise.jdx.dev/)-ისთვის:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

თუ არ იყენებთ Mise-ს, უნდა დარწმუნდეთ, რომ `tuist` ხელმისაწვდომია სქემის გარემოში, რადგან Xcode post-actions არ იღებენ თქვენი shell-ის `PATH`-ს. [Homebrew](https://brew.sh/)-ის ინსტალაციებისთვის:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## ბილდის ინსაიტები CI-ში {#continuous-integration}

CI-ზე ბილდის ინსაიტების თრეკინგისთვის, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">ავთენტიფიცირებული</.localized_link>.

Xcodebuild-ზე დაფუძნებული CI-ისთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როცა იძახებთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე, საჭირო აქტივობის ლოგები და შედეგის ბანდლები არ გენერირდება და `tuist inspect build` ვერ აანალიზებს ბილდს.

## მანქანის მეტრიკები {#machine-metrics}

ბილდის ინსაიტები შეიძლება შეიცავდეს მანქანის დონის შესრულების მეტრიკებს (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც ფიქსირდება ბილდის დროს. ამის ჩასართავად, დააყენეთ მსუბუქი ფონური დემონი, რომელიც უწყვეტად იღებს სისტემის მეტრიკებს:

```bash
tuist setup insights
```

ეს აწარმოებს ლოკალურ დემონს, რომელიც ფონურად იღებს მეტრიკებს. მონაცემებს ავტომატურად იღებს `tuist inspect build` და ატვირთავს ბილდის ანგარიშთან ერთად.

> [!TIP]
> **Ci**
>
> გაუშვით `tuist setup insights` თქვენს CI მანქანებზე ბილდამდე, რათა ასევე აღიბეჭდოს მანქანის მეტრიკები.

მანქანის მეტრიკების შეგროვების შესაჩერებლად, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს დემონის LaunchAgent-ს, შლის მის plist-ს და წაშლის აღებულ მეტრიკებსა და დემონის ლოგებს `~/.local/state`-დან, ასე რომ ფონზე არაფერი დარჩება გაშვებული.


## მორგებული მეტამონაცემები {#custom-metadata}

შეგიძლიათ მიამაგროთ მეტამონაცემები ბილდებს გარემოს ცვლადებით ფილტრაციის გასაუმჯობესებლად.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | რამდენიმე ტეგი ერთ ცვლადში. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | გასაღები-მნიშვნელობის წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს shell-ში ბილდის გამოძახებამდე:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
