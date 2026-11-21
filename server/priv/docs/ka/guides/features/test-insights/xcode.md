---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist-ის ტესტების ანალიტიკით თვალყური ადევნეთ Xcode-ის ტესტების მონაცემებს, რათა გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გაძლევთ Xcode ტესტების ანალიტიკას, რათა მონიტორინგი გაუწიოთ თქვენი ტესტების ნაკრების ჯანმრთელობას, გამოავლინოთ ნელი ტესტები ან სწრაფად გაერკვიეთ CI-ის გაშვებების ჩავარდნის მიზეზებში. როგორც კი თქვენი ტესტების ნაკრები იზრდება, უფრო და უფრო რთული ხდება ისეთი ტენდენციების აღმოჩენა, როგორიცაა თანდათანობითი შენელება ან დროდადრო წარმოქმნილი შეცდომები. Tuist Test Insights გთავაზობთ საჭირო გამჭვირვალობას, რათა შეინარჩუნოთ სწრაფი და საიმედო ტესტების ნაკრები.

Test Insights-ის საშუალებით შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდა ჩემი ტესტები უფრო ნელი? რომელი ტესტები?
- რომელი ტესტებია არასტაბილური და მოითხოვს ყურადღებას?
- რატომ ჩავარდა ჩემი CI-ის გაშვება?

## კონფიგურაცია {#setup}

ტესტების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ ბრძანება `tuist inspect test`, თუ მას დაამატებთ თქვენი სქემის ტესტის post-action-ში:

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
> თქვენი გარემოს `PATH` გარემოს ცვლადი არ გადაეცემა სქემის post-action-ს, ამიტომ უნდა გამოიყენოთ Mise-ის აბსოლუტური ბილიკი, რომელიც დამოკიდებულია Mise-ის ინსტალაციის მეთოდზე. ასევე, არ დაგავიწყდეთ ააწყოთ ბილდის პარამეტრები თქვენი პროექტის სამიზნიდან (target), რათა შეძლოთ Mise-ის გაშვება $SRCROOT-ით მითითებული დირექტორიიდან.

თქვენი ტესტების გაშვებები ახლა ფიქსირდება, სანამ თქვენ შესული ხართ თქვენს Tuist ანგარიშზე. თქვენს ტესტების ანალიტიკას შეგიძლიათ მიუწვდეთ Tuist დაშბორდზე და ნახოთ, როგორ იცვლება ისინი დროთა განმავლობაში:

![დაშბორდი ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ჩაუღრმავდეთ თითოეულ ცალკეულ ტესტსაც, მაგალითად, CI-ზე შეცდომების ან ნელი ტესტების დიაგნოსტიკისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავს `tuist inspect test` post-action-ს.
>
> თუ არ გაინტერესებთ ავტომატურად გენერირებულ სქემებში ტესტების ანალიტიკის თვალყურის დევნა, გათიშეთ ისინი [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გენერაციის პარამეტრის გამოყენებით.

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

CI-ზე ტესტების ანალიტიკის თვალყურის დევნისთვის უნდა დარწმუნდეთ, რომ თქვენი CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიფიცირებული</.localized_link>.

დამატებით, თქვენ დაგჭირდებათ ერთ-ერთი შემდეგი:
- გამოიყენეთ ბრძანება <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც იძახებთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებაში.

როდესაც `xcodebuild` ამოწმებს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო შედეგების ბანდლების ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git ისტორია {#git-history}

CI-ზე Tuist ასევე ატვირთავს checkout-ის კომიტების ისტორიას: კომიტების SHA-ებს, მათ მშობლებს, კომიტების თარიღებს და იმ ბრენჩს, რომელზეც გაშვება და მისი pull request-ის საბაზისო ბრენჩი იყო. არ იტვირთება ფაილების შინაარსი, კომიტების შეტყობინებები ან ავტორები. ეს ინფორმაცია ეუბნება Tuist-ს, რომელი კომიტები მოხვდა თქვენს საბაზისო ბრენჩზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზისო ბრენჩი, ითხოვს remote-დან მის უახლეს კომიტს (`git ls-remote`). კოდის დაფარვის გარეთ ისტორიას არ იღებს. კოდის დაფარვისას ზედაპირული (shallow) checkout ღრმავდება ფაილების შინაარსის გარეშე, რათა იპოვოს, საიდან გადაიხარა pull request და მიაღწიოს Tuist-ისთვის უკვე არსებულ კომიტებს, ამიტომ კომიტი არასდროს იტვირთება მშობლის გარეშე, რომელზეც ის ეყრდნობა.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ტვირთავს Git-ის ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, remote-თან დაკავშირების გარეშე. |
