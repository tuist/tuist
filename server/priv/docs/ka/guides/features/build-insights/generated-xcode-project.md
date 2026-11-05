---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "თუისტით გენერირებული Xcode პროექტის ბილდის ანალიტიკის თვალყურის დევნება Tuist-ის დაშბორდზე."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-build-insights}

> [!NOTE]
> ავტომატურად გენერირებულ სქემებს ავტომატურად ემატებათ `tuist inspect build` post-action.

>
> თუ არ გსურთ ბილდის ინსაიტების თვალყურის დევნა გენერირებულ სქემებში, გათიშეთ ეს ფუნქცია [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)-ის გამოყენებით.

თუ იყენებთ გენერირებულ პროექტებს მორგებული სქემებით, post-action თავად უნდა დაამატოთ. [Mise](https://mise.jdx.dev/)-ისთვის:

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

თუ არ იყენებთ Mise-ს, უნდა დარწმუნდეთ, რომ `tuist` ხელმისაწვდომია სქემის გარემოში, რადგან Xcode-ის post-actions არ იღებენ თქვენი shell-ის `PATH`-ს. [Homebrew](https://brew.sh/)-ით ინსტალაციის შემთხვევაში:

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

CI-ში ბილდის ინსაიტების თვალყურის სადევნად, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">ავტორიზებული</.localized_link>.

Xcodebuild-ზე დაფუძნებული CI-სთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> `xcodebuild` ქმედებების გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე, საჭირო აქტივობის ლოგები და შედეგების ბანდლები არ გენერირდება და `tuist inspect build` ვერ შეძლებს ბილდის ანალიზს.

## მანქანის მეტრიკები {#machine-metrics}

ბილდის ინსაიტები შეიძლება მოიცავდეს მანქანის დონის შესრულების მეტრიკებს (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც ფიქსირდება ბილდის დროს. ამის ჩასართავად, დააყენეთ მსუბუქი ფონური დემონი, რომელიც უწყვეტად აგროვებს სისტემურ მეტრიკებს:

```bash
tuist setup insights
```

ეს აწარმოებს ლოკალურ დემონს, რომელიც ფონურად აგროვებს მეტრიკებს. მონაცემებს ავტომატურად იღებს `tuist inspect build` და ატვირთავს ბილდის ანგარიშთან ერთად.

> [!TIP]
> **Ci**
>
> გაუშვით `tuist setup insights` თქვენს CI მანქანებზე ბილდამდე, რათა იქაც აღიბეჭდოს მანქანის მეტრიკები.

მანქანის მეტრიკების შეგროვების შესაჩერებლად, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს დემონის LaunchAgent-ს, შლის მის plist-ს და ასუფთავებს შეგროვებულ მეტრიკებსა და დემონის ლოგებს `~/.local/state`-დან, ისე რომ ფონზე არაფერი დარჩეს გაშვებული.


## მორგებული მეტამონაცემები {#custom-metadata}

ბილდებს შეგიძლიათ მიამაგროთ მეტამონაცემები გარემოს ცვლადების საშუალებით, რათა გაუმჯობესდეს ფილტრაცია.

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
