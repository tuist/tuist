---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-build-insights}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად მოიცავენ `tuist inspect build` post-action-ს.

>
> თუ არ გსურთ აგების ინფორმაციის თვალყურის დევნა გენერირებულ სქემებში, გათიშეთ ის [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)-ის გამოყენებით.

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

თუ არ იყენებთ Mise-ს, უნდა დარწმუნდეთ, რომ `tuist` ხელმისაწვდომია სქემის გარემოში, რადგან Xcode-ის post-actions არ იღებენ თქვენი shell-ის `PATH`-ს. [Homebrew](https://brew.sh/)-ის ინსტალაციებისთვის:

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

## აგების ინფორმაცია CI-ში {#continuous-integration}

CI-ში აგების ინფორმაციის თვალყურის სადევნად, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">აუთენტიფიცირებული</.localized_link>.

Xcodebuild-ზე დაფუძნებული CI-ისთვის თქვენ უნდა:
- გამოიყენოთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც იწვევთ `xcodebuild` ქმედებებს.
- დაამატოთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე, საჭირო აქტივობის ლოგები და შედეგების ბანდლები არ გენერირდება და `tuist inspect build` ვერ შეძლებს აგების ანალიზს.

## მანქანის მეტრიკები {#machine-metrics}

აგების ინფორმაცია შეიძლება მოიცავდეს მანქანის დონის შესრულების მეტრიკებს (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც აღიბეჭდება აგების დროს. ამის ჩასართავად, დააყენეთ მსუბუქი ფონური დემონი, რომელიც უწყვეტად იღებს სისტემის მეტრიკებს:

```bash
tuist setup insights
```

ეს აწარმოებს ლოკალურ დემონს, რომელიც ფონურად იღებს მეტრიკებს. მონაცემები ავტომატურად იჭერება `tuist inspect build`-ის მიერ და იტვირთება აგების ანგარიშთან ერთად.

> [!TIP]
> **Ci**
>
> გაუშვით `tuist setup insights` თქვენს CI მანქანებზე აგებამდე, რათა ასევე აღიბეჭდოს მანქანის მეტრიკები.

მანქანის მეტრიკების შეგროვების შესაჩერებლად, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს დემონის LaunchAgent-ს, აშორებს მის plist-ს და შლის შეგროვებულ მეტრიკებსა და დემონის ლოგებს `~/.local/state`-დან, ასე რომ ფონზე არაფერი რჩება გაშვებული.


## მორგებული მეტამონაცემები {#custom-metadata}

შეგიძლიათ დააკავშიროთ მეტამონაცემები აგებებთან გარემოს ცვლადების გამოყენებით ფილტრაციის გასაუმჯობესებლად.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | მრავალი ტეგი ერთ ცვლადში. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | ღირებულებათა წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს shell-ში აგების გამოძახებამდე:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
