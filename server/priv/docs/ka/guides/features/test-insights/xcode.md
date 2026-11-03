---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აწარმოეთ Xcode ტესტების ანალიტიკა, რათა Tuist Test Insights-ის საშუალებით გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode-ის ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გაძლევთ Xcode-ის ტესტების ანალიტიკას, რათა თვალყური ადევნოთ თქვენი ტესტების ნაკრების ჯანმრთელობას — გამოავლინოთ ნელი ტესტები ან სწრაფად გაარკვიოთ CI-ის წარუმატებელი გაშვების მიზეზები. როგორც კი თქვენი ტესტების ნაკრები იზრდება, უფრო რთული ხდება ისეთი ტენდენციების შენიშვნა, როგორიცაა ტესტების თანდათანობითი შენელება ან პერიოდული შეცდომები. Tuist Test Insights გაძლევთ საჭირო ხილვადობას, რათა შეინარჩუნოთ სწრაფი და საიმედო ტესტების ნაკრები.

Test Insights-ის მეშვეობით შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდა ჩემი ტესტები უფრო ნელი? რომელი ტესტები?
- რომელი ტესტებია არასტაბილური და ყურადღებას საჭიროებს?
- რატომ ვერ მოხერხდა ჩემი CI-ის გაშვება?

## მოწყობა {#setup}

ტესტების თვალთვალყურის დევნების დასაწყებად, შეგიძლიათ გამოიყენოთ ბრძანება `tuist inspect test`, თუ მას დაამატებთ თქვენი სქემის ტესტის post-action-ში:

![Post-action ტესტების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

თუ იყენებთ [Mise](https://mise.jdx.dev/)-ს, თქვენს სკრიპტს დასჭირდება `tuist`-ის აქტივაცია post-action-ის გარემოში:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise და პროექტის გზები**
>
> თქვენი გარემოს `PATH` გარემოს ცვლადი არ გადაეცემა სქემის post-action-ს, ამიტომ უნდა გამოიყენოთ Mise-ის აბსოლუტური გზა, რომელიც დამოკიდებული იქნება Mise-ის ინსტალაციის მეთოდზე. ასევე, არ დაგავიწყდეთ ააწყოთ ბილდის პარამეტრები თქვენი პროექტის ერთ-ერთი target-ის მიხედვით, რათა შეძლოთ Mise-ის გაშვება $SRCROOT-ით მითითებული დირექტორიიდან.

თქვენი ტესტების გაშვებები ახლა თვალყურს ედევნება, სანამ თქვენ შესული ხართ თქვენს Tuist-ის ანგარიშზე. შეგიძლიათ მიუწვდეთ თქვენს ტესტების ანალიტიკას Tuist-ის დაშბორდზე და ნახოთ, როგორ იცვლება ისინი დროთა განმავლობაში:

![დაშბორდი ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ღრმად ჩაუღრმავდეთ თითოეულ ინდივიდუალურ ტესტს, მაგალითად, CI-ზე შეცდომების ან ნელი ტესტების დიაგნოსტიკისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავს `tuist inspect test` post-action-ს.

>
> თუ არ გაინტერესებთ ავტომატურად გენერირებულ სქემებში ტესტების ანალიტიკის თვალყურის დევნა, გამორთეთ ისინი [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გენერაციის პარამეტრის გამოყენებით.

თუ იყენებთ გენერირებულ პროექტებს მორგებული სქემებით, შეგიძლიათ დააყენოთ post-actions ტესტების ანალიტიკისთვის:

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

CI-ზე ტესტების ანალიტიკის თვალყურის დევნისთვის, უნდა დარწმუნდეთ, რომ თქვენი CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">ავტორიზებული</.localized_link>.

დამატებით, დაგჭირდებათ ერთ-ერთი შემდეგი ვარიანტი:
- გამოიყენეთ ბრძანება <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც იძახებთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებას.

როდესაც `xcodebuild` ტესტავს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო შედეგების ბანდლის ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git-ის ისტორია {#git-history}

CI-ზე Tuist ასევე ატვირთავს checkout-ის კომიტების ისტორიას: კომიტების SHA-ებს, მათ მშობლებს, კომიტების თარიღებს და იმ შტოს, რომელზეც გაშვება და მისი pull request-ის საბაზისო შტო იყო. არ აიტვირთება ფაილების შინაარსი, კომიტების შეტყობინებები ან ავტორები. ეს ეუბნება Tuist-ს, თუ რომელი კომიტები მოხვდა თქვენს საბაზისო შტოზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზისო შტო, ითხოვს მის უახლეს კომიტს (`git ls-remote`). კოდის დაფარვის გარეთ, ისტორიას არ იწერს.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ატვირთავს Git-ის ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, remote-თან დაკავშირების გარეშე. |
