---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Derleme içgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde, Tuist tarafından oluşturulan bir Xcode projesinin derleme analizlerini takip edin."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-build-insights}

> [!NOTE]
> Otomatik oluşturulan şemalar, `tuist inspect build` post-action'ını otomatik olarak içerir.
>
> Oluşturulan şemalarda derleme içgörülerini izlemek istemiyorsanız, bunu [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) kullanarak devre dışı bırakın.

Özel şemalara sahip oluşturulmuş projeler kullanıyorsanız, post-action'ı kendiniz eklemeniz gerekir. [Mise](https://mise.jdx.dev/) için:

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

Mise kullanmıyorsanız, Xcode post-action'ları kabuğunuzun `PATH` değerini miras almadığından `tuist` öğesinin şema ortamında kullanılabilir olduğundan emin olmanız gerekir. [Homebrew](https://brew.sh/) kurulumları için:

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
