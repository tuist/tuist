---
{
  "title": "Xcode",
  "titleTemplate": ":title · სნაპშოტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გადაიღეთ Xcode პროექტის ყველა SwiftUI პრივიუ და გადახედეთ ცვლილებებს Tuist-ში."
}
---
# Xcode სნეპშოტები {#xcode-snapshots}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - სნეპშოტები ჩართულია თქვენი ანგარიშისთვის. ისინი ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი: [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev) წვდომის მოსათხოვნად.
> - პროექტი <.localized_link href="/guides/get-started/existing-xcode-project">დაკავშირებული Tuist-თან</.localized_link>.
> - iOS 17 ან macOS 14 პრივიუების რენდერინგისთვის.

ბიბლიოთეკა [tuist/snapshots](https://github.com/tuist/snapshots) თქვენი აპლიკაციის ყველა SwiftUI პრივიუს გამოსახულებად აქცევს, რათა სნეპშოტ ტესტები ხელით არ დაწეროთ. `tuist xcodebuild test` ატვირთავს გამოსახულებებს გაშვების შემდეგ, ხოლო Tuist ადარებს მათ <.localized_link href="/guides/features/snapshots#how-it-works">საბაზისო ვერსიასთან</.localized_link>.

## მოწყობა {#set-up}

1. Xcode-ში დაამატეთ პაკეტი `https://github.com/tuist/snapshots`, ვერსიიდან `0.1.0`.
2. შექმენით იუნით ტესტის თარგეთი, რომელსაც მასპინძლობს თქვენი აპლიკაცია, მაგალითად `AppSnapshotTests`, და მიამაგრეთ მას პაკეტის პროდუქტი `TuistSnapshotsTesting`.
3. დაამატეთ ტესტის კლასი ამ თარგეთზე. ყოველი პრივიუ ხდება ცალკე ტესტი:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. დაამატეთ სქემა, რომელიც გაუშვებს თარგეთს, მაგალითად `AppSnapshots`. სქემა სახელს არქმევს სნეპშოტების ნაკრებს.

## გაშვება {#run}

გაუშვით ტესტები `tuist xcodebuild test`-ის მეშვეობით, ყოველთვის ერთსა და იმავე სიმულატორზე, რადგან სხვადასხვა მოწყობილობა სხვადასხვა ზომის გამოსახულებებს რენდერავს:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI-ში ტესტების მიერ რენდერირებული გამოსახულებები აიტვირთება გაშვების შემდეგ, და ბრძანება ასრულებს შეცდომით, თუ ისინი შეიცვალა და ცვლილებები არავინ დაამტკიცა. ლოკალური გაშვებები არაფერს ტვირთავს, რადგან ისინი ატვირთავდნენ დაუკომიტებელ ცვლილებებს.

<!-- @snippet: ./_previews-library -->
