---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · სნეპშოტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინახეთ Tuist-ით გენერირებული პროექტის ყოველი SwiftUI პრევიუ და გადახედეთ ცვლილებებს Tuist-ში."
}
---
# გენერირებული Xcode პროექტის სნეპშოტები {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - სნეპშოტები ჩართულია თქვენს ანგარიშზე. ისინი ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი: [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev) წვდომის მოსათხოვნად.
> - პროექტი, რომელიც <.localized_link href="/guides/get-started/generated-xcode-project">Tuist-თან არის დაკავშირებული</.localized_link>.
> - iOS 17 ან macOS 14 პრივიუების რენდერინგისთვის.

[tuist/snapshots](https://github.com/tuist/snapshots) ბიბლიოთეკა თქვენი აპლიკაციის ყოველ SwiftUI პრივიუს გამოსახულებად გარდაქმნის, რათა სნეპშოტ ტესტები ხელით არ დაწეროთ. `tuist test` ატვირთავს გამოსახულებებს გაშვების შემდეგ, ხოლო Tuist ადარებს მათ <.localized_link href="/guides/features/snapshots#how-it-works">საწყის ვერსიასთან</.localized_link>.

## გამართვა {#set-up}

დაამატეთ პაკეტი `Tuist/Package.swift`-ში:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

შემდეგ დაამატეთ ერთეულის ტესტის სამიზნე, რომელიც დამოკიდებულია თქვენს აპლიკაციაზე და `TuistSnapshotsTesting`-ზე, ასევე სქემა, რომელიც მას გაუშვებს. სქემა განსაზღვრავს სნეპშოტების ნაკრების სახელს:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

დაამატეთ ტესტის კლასი სამიზნეში. ყოველი პრივიუ ხდება ცალკე ტესტი:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

გაუშვით `tuist install` პაკეტის ჩამოსატვირთად.

## გაშვება {#run}

გაუშვით სქემა `tuist test`-ით, ყოველთვის ერთსა და იმავე სიმულატორზე, რადგან სხვა მოწყობილობა სხვა ზომის გამოსახულებებს აგენერირებს:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

CI-ში, ტესტების მიერ შექმნილი გამოსახულებები იტვირთება გაშვების შემდეგ, და ბრძანება ვერდება, თუ ისინი შეიცვალა და ცვლილებები არავინ დაამტკიცა. ლოკალური გაშვებები არაფერს ტვირთავს, რადგან ისინი დააკომიტებელ ცვლილებებს ატვირთავდნენ.

> [!TIP]
> <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირებით</.localized_link>, სნეპშოტ ტესტის სამიზნე გამოიტოვება მხოლოდ მაშინ, როცა მისი გამოსახულებები გაიარეს ან დამტკიცდა, ასე რომ ხელახლა გაშვება ვერ გამოტოვებს სამიზნეს, რომლის ცვლილებებიც არავინ შეამოწმა. როცა გაშვება გამოტოვებს სამიზნეებს, გამოსახულებები, რომლებიც მან არ შექმნა, ითვლება გამოტოვებულად და არა წაშლილად.

<!-- @snippet: ./_previews-library -->
