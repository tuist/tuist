---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ადევნეთ თვალი Xcode-ის ტესტების ანალიტიკას, რათა Tuist Test Insights-ის მეშვეობით გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode-ის ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გაძლევთ Xcode-ის ტესტების ანალიტიკას, რათა მონიტორინგი გაუწიოთ თქვენი ტესტების ნაკრების ჯანმრთელობას — გამოავლინოთ ნელი ტესტები ან სწრაფად გაარკვიოთ CI-ის ჩავარდნილი გაშვებების მიზეზები. როგორც კი თქვენი ტესტების ნაკრები იზრდება, უფრო რთული ხდება ისეთი ტენდენციების შენიშვნა, როგორიცაა თანდათანობითი შენელება ან პერიოდული ჩავარდნები. Tuist Test Insights გთავაზობთ საჭირო ხილვადობას, რათა შეინარჩუნოთ სწრაფი და საიმედო ტესტების ნაკრები.

Test Insights-ის მეშვეობით შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდა თუ არა ჩემი ტესტები უფრო ნელი? რომლები?
- რომელი ტესტებია არასტაბილური და ყურადღებას საჭიროებს?
- რატომ ჩავარდა ჩემი CI-ის გაშვება?

## მოწყობა {#setup}

ტესტების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ ბრძანება `tuist inspect test`, მისი სქემის ტესტის post-action-ში დამატებით:

![post-action ტესტების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

თუ იყენებთ [Mise](https://mise.jdx.dev/)-ს, თქვენს სკრიპტს post-action-ის გარემოში `tuist`-ის აქტივაცია დასჭირდება:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise და პროექტის ბილიკები**
>
> თქვენი გარემოს `PATH` გარემოს ცვლადი არ გადაეცემა სქემის post-action-ს, ამიტომ მოგიწევთ Mise-ის აბსოლუტური ბილიკის გამოყენება, რომელიც დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ასევე, არ დაგავიწყდეთ ააწყოთ ბილდის პარამეტრები თქვენი პროექტის სამიზნიდან, რათა შეძლოთ Mise-ის გაშვება $SRCROOT-ით მითითებული დირექტორიიდან.

თქვენი ტესტების გაშვებები ახლა ფიქსირდება, სანამ თქვენ შესული ხართ თქვენს Tuist-ის ანგარიშზე. შეგიძლიათ ნახოთ თქვენი ტესტების ანალიტიკა Tuist-ის დაფაზე და დააკვირდეთ, როგორ იცვლება ისინი დროთა განმავლობაში:

![დაფა ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ღრმად ჩაუღრმავდეთ თითოეულ ტესტს, მაგალითად, CI-ზე ჩავარდნების ან ნელი ტესტების დებაგინგისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავს `tuist inspect test` post-action-ს.
>
> თუ არ გაინტერესებთ ტესტების ანალიტიკის თვალყურის დევნა ავტომატურად გენერირებულ სქემებში, გამორთეთ ისინი [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გენერაციის პარამეტრის გამოყენებით.

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

თუ არ იყენებთ Mise-ს, თქვენი სკრიპტები შეიძლება გამარტივდეს:

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

CI-ზე ტესტების ანალიტიკის თვალყურის დევნისთვის, უნდა დარწმუნდეთ, რომ თქვენი CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავტორიზებული</.localized_link>.

დამატებით, დაგჭირდებათ ერთ-ერთი შემდეგი:
- გამოიყენეთ ბრძანება <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> `xcodebuild` ქმედებების გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებას.

როდესაც `xcodebuild` ამოწმებს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო შედეგის ბანდლების ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git-ის ისტორია {#git-history}

CI-ზე Tuist ასევე ატვირთავს checkout-ის კომიტების ისტორიას: კომიტების SHA-ებს, მათ მშობლებს, კომიტების თარიღებს და იმ ბრენჩს, რომელზეც იყო გაშვება და მისი pull request-ის საბაზო ბრენჩი. არ იტვირთება ფაილების შინაარსი, კომიტების შეტყობინებები ან ავტორები. ეს ეუბნება Tuist-ს, რომელი კომიტები მოხვდა თქვენს საწყის ბრენჩზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზო ბრენჩი, ითხოვს უახლეს კომიტს რემოტიდან (`git ls-remote`). კოდის დაფარვის გარეთ, ისტორიას არ იღებს. კოდის დაფარვისას, ზედაპირული checkout ღრმავდება, ფაილების შინაარსის გარეშე, რათა იპოვოს, საიდან გადაუხვია pull request-მა და მიაღწიოს იმ კომიტებს, რომლებიც Tuist-ს უკვე აქვს, ამიტომ კომიტი არასდროს იტვირთება მშობლის გარეშე, რომელზეც ის ეყრდნობა.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ტვირთავს Git-ის ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, რემოტთან დაკავშირების გარეშე. |
