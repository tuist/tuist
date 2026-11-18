---
{
  "title": "Xcode ტესტების ანალიტიკა",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist-ის ტესტების ანალიტიკით თვალყური ადევნეთ Xcode ტესტების მეტრიკებს, რათა გამოავლინოთ ნელი და არასტაბილური ტესტები."
}
---
# Xcode ტესტების ანალიტიკა {#xcode-test-insights}

Tuist Test Insights გაძლევთ Xcode ტესტების ანალიტიკას, რათა მონიტორინგი გაუწიოთ თქვენი ტესტების სუიტის ჯანმრთელობას ნელი ტესტების იდენტიფიცირებით ან CI-ს ჩავარდნილი გაშვებების სწრაფად გაგებით. როგორც კი თქვენი ტესტების სუიტა იზრდება, უფრო და უფრო რთული ხდება ისეთი ტენდენციების შენიშვნა, როგორიცაა თანდათანობით ნელდება ტესტები ან პერიოდული ჩავარდნები. Tuist Test Insights გაძლევთ საჭირო ხილვადობას, რათა შეინარჩუნოთ სწრაფი და სანდო ტესტების სუიტა.

Test Insights-ის საშუალებით, შეგიძლიათ უპასუხოთ ისეთ კითხვებს, როგორიცაა:
- გახდნენ თუ არა ჩემი ტესტები უფრო ნელი? რომელი ერთები?
- რომელი ტესტებია არასტაბილური (flaky) და საჭიროებს ყურადღებას?
- რატომ ჩავარდა ჩემი CI გაშვება?

## მოწყობა {#setup}

ტესტების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect test` ბრძანება, მისი სქემის ტესტის post-action-ში დამატებით:

![Post-action ტესტების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

თუ იყენებთ [Mise](https://mise.jdx.dev/)-ს, თქვენს სკრიპტს დასჭირდება `tuist`-ის აქტივაცია post-action გარემოში:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise და პროექტის გზები**
>
> თქვენი გარემოს `PATH` გარემოს ცვლადი არ გადაეცემა სქემის post-action-ს და ამიტომ უნდა გამოიყენოთ Mise-ის აბსოლუტური გზა, რაც დამოკიდებული იქნება იმაზე, თუ როგორ დააინსტალირეთ Mise. ასევე, არ დაგავიწყდეთ ააწყოთ build პარამეტრები თქვენი პროექტის target-დან, რათა შეძლოთ Mise-ის გაშვება $SRCROOT-ით მითითებული დირექტორიიდან.

თქვენი ტესტების გაშვებები ახლა თვალყურს ედევნება, სანამ შესული ხართ თქვენს Tuist ანგარიშში. შეგიძლიათ მიუწვდეთ თქვენს ტესტების ანალიტიკას Tuist დაშბორდზე და ნახოთ, როგორ იცვლება ისინი დროთა განმავლობაში:

![დაშბორდი ტესტების ანალიტიკით](/images/guides/features/build-insights/tests-dashboard.png)

ზოგადი ტენდენციების გარდა, შეგიძლიათ ღრმად ჩაუღრმავდეთ თითოეულ ინდივიდუალურ ტესტს, მაგალითად, CI-ზე ჩავარდნების ან ნელი ტესტების დებაგინგისას:

![ტესტის დეტალები](/images/guides/features/build-insights/test-detail.png)

## გენერირებული პროექტები {#generated-projects}

> [!NOTE]
> ავტომატურად გენერირებული სქემები ავტომატურად შეიცავს `tuist inspect test` post-action-ს.
>
> თუ არ გაინტერესებთ ტესტების ანალიტიკის თვალყურის დევნა თქვენს ავტომატურად გენერირებულ სქემებში, გამორთეთ ისინი [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) გენერაციის პარამეტრის გამოყენებით.

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
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> ბრძანება `xcodebuild` მოქმედებების გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` გამოძახებას.

როდესაც `xcodebuild` ტესტავს თქვენს პროექტს `-resultBundlePath`-ის გარეშე, საჭირო result bundle ფაილები არ გენერირდება. `tuist inspect test` post-action-ს ეს ფაილები სჭირდება თქვენი ტესტების ანალიზისთვის.

### Git ისტორია {#git-history}

CI-ზე, Tuist ასევე ატვირთავს checkout-ის commit ისტორიას: commit SHA-ებს, მათ მშობლებს, commit თარიღებს და იმ branch-ს, რომელზეც იყო გაშვება და მისი pull request-ის საბაზო branch. არ აიტვირთება ფაილების შინაარსი, commit შეტყობინებები ან ავტორები. ეს არის ის, რაც ეუბნება Tuist-ს, რომელი commits მოხვდა თქვენს საბაზო branch-ზე, მაგალითად, ისინი, რომლებიც merge queue-მ შეამოწმა. Tuist კითხულობს ისტორიას, რომელიც checkout-ს უკვე აქვს, და როდესაც checkout-ს არ აქვს საბაზო branch, სთხოვს remote-ს მის უახლეს commit-ს (`git ls-remote`). კოდის დაფარვის (code coverage) გარეთ, ის არ იღებს ისტორიას.

| ცვლადი | ეფექტი |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | არ კითხულობს და არ ტვირთავს Git-ის რაიმე ისტორიას. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | კითხულობს მხოლოდ checkout-ს, remote-თან დაკავშირების გარეშე. |
