---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist Test Insights-ის საშუალებით თვალყური ადევნეთ Xcode ტესტების ანალიტიკას, რათა გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode-ის ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გაძლევთ Xcode-ის ტესტების ანალიტიკას, რათა მონიტორინგი გაუწიოთ თქვენი ტესტების ნაკრების ჯანმრთელობას ნელი ტესტების იდენტიფიცირებით ან CI-ის ჩავარდნილი გაშვებების სწრაფად გაგებით. როგორც კი თქვენი ტესტების ნაკრები იზრდება, ტენდენციების, როგორიცაა თანდათანობითი შენელება ან პერიოდული ჩავარდნები, აღმოჩენა უფრო რთული ხდება. Tuist Test Insights გაძლევთ საჭირო ხილვადობას, რათა შეინარჩუნოთ სწრაფი და საიმედო ტესტების ნაკრები.

Test Insights-ის საშუალებით შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდა თუ არა ჩემი ტესტები უფრო ნელი? რომელი ტესტები?
- რომელი ტესტებია არასტაბილური და ყურადღებას საჭიროებს?
- რატომ ჩავარდა ჩემი CI-ის გაშვება?

## გამართვა {#setup}

ტესტების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ ბრძანება `tuist inspect test`, მისი სქემის ტესტის post-action-ში დამატებით:

![post-action ტესტების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

თუ იყენებთ [Mise](https://mise.jdx.dev/)-ს, თქვენს სკრიპტს დასჭირდება `tuist`-ის აქტივაცია post-action-ის გარემოში:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise და პროექტის გზები**
>
> თქვენი გარემოს ცვლადი `PATH` არ გადაეცემა სქემის post-action-ს, ამიტომ უნდა გამოიყენოთ Mise-ის აბსოლუტური გზა, რომელიც დამოკიდებული იქნება Mise-ის ინსტალაციის წესზე. ასევე, არ დაგავიწყდეთ ააწყოთ build-ის პარამეტრები თქვენი პროექტის target-დან, რათა შეძლოთ Mise-ის გაშვება $SRCROOT-ით მითითებული დირექტორიიდან.

თქვენი ტესტების გაშვებები ახლა თვალყურს ედევნება, სანამ თქვენ შესული ხართ თქვენს Tuist ანგარიშში. შეგიძლიათ მიუწვდეთ თქვენს ტესტების ანალიტიკას Tuist-ის დაშბორდზე და ნახოთ, როგორ იცვლება ისინი დროთა განმავლობაში:

![დაშბორდი ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ღრმად ჩაუღრმავდეთ თითოეულ ინდივიდუალურ ტესტს, მაგალითად, CI-ზე ჩავარდნების ან ნელი ტესტების დიაგნოსტიკისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად მოიცავს post-action-ს `tuist inspect test`.
>
> თუ არ გაინტერესებთ ტესტების ანალიტიკის თვალყურის დევნა ავტომატურად გენერირებულ სქემებში, გამორთეთ ისინი გენერაციის პარამეტრის [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გამოყენებით.

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

თუ არ იყენებთ Mise-ს, თქვენი სკრიპტები შეიძლება გამარტივდეს შემდეგნაირად:

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
- გამოიყენეთ ბრძანება <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> `xcodebuild` მოქმედებების გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებაში.

როდესაც `xcodebuild` ამოწმებს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო შედეგის bundle ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git-ის ისტორია {#git-history}

CI-ზე, Tuist ასევე ატვირთებს checkout-ის commit-ების ისტორიას: commit SHA-ებს, მათ მშობლებს, commit-ების თარიღებს და იმ branch-ს, რომელზეც გაშვება და მისი pull request-ის საბაზო branch იყო. არ იტვირთება ფაილების შინაარსი, commit-ების შეტყობინებები ან ავტორები. ეს არის ის, რაც ეუბნება Tuist-ს, რომელი commit-ები მოხვდა თქვენს საბაზო branch-ზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზო branch, ითხოვს უახლეს commit-ს remote-დან (`git ls-remote`). კოდის დაფარვის გარეშე, ის არ იღებს ისტორიას. კოდის დაფარვისას, ზედაპირული checkout ღრმავდება, ფაილების შინაარსის გარეშე, რათა იპოვოს, საიდან გადაეხტა pull request და მიაღწიოს იმ commit-ებს, რომლებიც Tuist-ს უკვე აქვს, ასე რომ, commit არასდროს იტვირთება მშობლის გარეშე, რომელზეც ის ეყრდნობა.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ტვირთავს Git-ის ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, remote-თან დაკავშირების გარეშე. |
