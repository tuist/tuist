---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აკონტროლეთ ბილდის ანალიტიკა Tuist-ით გენერირებული Xcode პროექტისთვის Tuist დაშბორდზე."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-build-insights}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავენ `tuist inspect build` post-action-ს.
>
> თუ არ გსურთ ბილდის ინსაიტების თრეკინგი გენერირებულ სქემებში, გათიშეთ ის [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)-ის გამოყენებით.

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

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
