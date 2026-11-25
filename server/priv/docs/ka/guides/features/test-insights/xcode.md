---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აკონტროლეთ Xcode-ის ტესტების ანალიტიკა, რათა Tuist Test Insights-ით გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გთავაზობთ Xcode ტესტების ანალიტიკას, რათა თვალყური ადევნოთ თქვენი ტესტების ნაკრების მდგომარეობას — გამოავლინოთ ნელი ტესტები ან სწრაფად გაიგოთ CI-ს წარუმატებელი გაშვების მიზეზები. როგორც კი თქვენი ტესტების ნაკრები იზრდება, უფრო რთული ხდება ისეთი ტენდენციების შენიშვნა, როგორიცაა ტესტების თანდათანობითი შენელება ან დროდადრო წარუმატებლობები. Tuist Test Insights გაძლევთ საჭირო ხილვადობას, რათა შეინარჩუნოთ სწრაფი და საიმედო ტესტების ნაკრები.

Test Insights-ის მეშვეობით შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდა ჩემი ტესტები უფრო ნელი? რომლები?
- რომელი ტესტებია არასტაბილური და ყურადღებას საჭიროებს?
- რატომ ვერ მოხერხდა ჩემი CI გაშვება?

## მოწყობა {#setup}

ტესტების თვალთვალის დასაწყებად შეგიძლიათ გამოიყენოთ ბრძანება `tuist inspect test`, თუ მას დაამატებთ თქვენი სქემის ტესტის post-action-ში:

![Post-action ტესტების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

თუ იყენებთ [Mise](https://mise.jdx.dev/)-ს, თქვენს სკრიპტს post-action-ის გარემოში `tuist` უნდა გაააქტიუროს:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise და პროექტის ბილიკები**
>
> თქვენი გარემოს `PATH` გარემოს ცვლადი სქემის post-action-ში არ გადაეცემა, ამიტომ უნდა გამოიყენოთ Mise-ის აბსოლუტური ბილიკი, რომელიც დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ასევე, არ დაგავიწყდეთ პროექტის სამიზნიდან (target) ააწყოთ აშენების პარამეტრები, რათა $SRCROOT-ით მითითებულ დირექტორიაში შეძლოთ Mise-ის გაშვება.

თქვენი ტესტების გაშვებები ახლა იწერება, სანამ თქვენ შესული ხართ თქვენს Tuist ანგარიშზე. შეგიძლიათ მიუწვდეთ თქვენს ტესტების ანალიტიკას Tuist-ის დაფაზე და ნახოთ, როგორ იცვლება ის დროთა განმავლობაში:

![დაფა ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ღრმად ჩაუღრმავდეთ თითოეულ ცალკეულ ტესტს, მაგალითად, CI-ზე წარუმატებლობების ან ნელი ტესტების დიაგნოსტიკისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავს `tuist inspect test` post-action-ს.
>
> თუ არ გაინტერესებთ ავტომატურად გენერირებულ სქემებში ტესტების ანალიტიკის თვალთვალი, გამორთეთ ისინი [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გენერაციის პარამეტრის გამოყენებით.

თუ იყენებთ გენერირებულ პროექტებს მორგებული სქემებით, შეგიძლიათ დააყენოთ post-action-ები ტესტების ანალიტიკისთვის:

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
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

თუ არ იყენებთ Mise-ს, თქვენი სკრიპტები შეიძლება გაამარტივოთ შემდეგნაირად:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## უწყვეტი ინტეგრაცია {#continuous-integration}

CI-ზე ტესტების ანალიტიკის თვალთვალისთვის უნდა დარწმუნდეთ, რომ თქვენი CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავტორიზებული</.localized_link>.

დამატებით, დაგჭირდებათ ერთ-ერთი შემდეგი:
- გამოიყენეთ ბრძანება <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც `xcodebuild` ქმედებებს ასრულებთ.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებაში.

როდესაც `xcodebuild` ამოწმებს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო შედეგების ბანდლების ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git-ის ისტორია {#git-history}

CI-ზე Tuist ასევე ატვირთავს checkout-ის კომიტების ისტორიას: კომიტების SHA-ებს, მათ მშობლებს, კომიტების თარიღებს და იმ დარგს, რომელზეც გაშვება და მისი pull request-ის საბაზისო დარგი იყო. ფაილების შინაარსი, კომიტების შეტყობინებები ან ავტორები არ იტვირთება. ეს არის ის, რაც Tuist-ს ეუბნება, რომელი კომიტები მოხვდა თქვენს საბაზისო დარგზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზისო დარგი, ითხოვს remote-დან მის უახლეს კომიტს (`git ls-remote`). კოდის დაფარვის გარეთ ისტორიას არ იღებს. კოდის დაფარვისას ზედაპირული checkout ღრმავდება, ფაილების შინაარსის გარეშე, რათა იპოვოს, საიდან განშტოვდა pull request და მიაღწიოს იმ კომიტებს, რომლებიც Tuist-ს უკვე აქვს, ასე რომ კომიტი არასდროს იტვირთება მშობლის გარეშე, რომელზეც ის ეყრდნობა.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ტვირთავს Git-ის ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, remote-თან დაკავშირების გარეშე. |
| `TUIST_GIT_BRANCH=<branch>` | არქმევს გაშვების დარგს, CI-ს პროვაიდერისა და checkout-ის წინ. დააყენეთ იმ CI სისტემებზე, რომლებსაც Tuist არ ცნობს და რომლებიც კომიტს ამოწმებენ დარგის ნაცვლად, რათა გაშვებებს ჰქონდეთ დარგი. |
