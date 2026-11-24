---
{
  "title": "Gradle",
  "titleTemplate": ":title · სნეპშოტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გადაიღეთ ყველა Compose პრივიუ სნეპშოტი ან ატვირთეთ Paparazzi-სა და Roborazzi-ს მიერ ჩაწერილი შედეგები Tuist Gradle პლაგინის გამოყენებით."
}
---
# Gradle სნეპშოტები {#gradle-snapshots}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - სნეპშოტები ჩართულია თქვენს ანგარიშზე. ისინი ამჟამად მხოლოდ მიწვევით ხელმისაწვდომია: [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev) წვდომის მოსათხოვნად.
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle პლაგინი</.localized_link>.
> - [Paparazzi](https://github.com/cashapp/paparazzi) ან [Roborazzi](https://github.com/takahirom/roborazzi) იმ მოდულებში, რომლებსაც სნეპშოტებს უღებთ.

Tuist Gradle პლაგინი ტვირთავს Paparazzi-ს და Roborazzi-ს მიერ ჩაწერილ გამოსახულებებს, ხოლო Tuist ადარებს მათ <.localized_link href="/guides/features/snapshots#how-it-works">ბაზისურ ვერსიასთან</.localized_link>. მოდულებში, სადაც Paparazzi გამოიყენება, პლაგინი ასევე ქმნის ტესტს, რომელიც აჩვენებს ყოველ Compose `@Preview`, რათა სნეპშოტ ტესტები ხელით არ დაწეროთ.

## მორგება {#set-up}

ჩართეთ სნეპშოტები თქვენს `settings.gradle.kts` ფაილში:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## გაშვება {#run}

CI-ში `./gradlew test` აჩვენებს პრივიუებს და ტვირთავს მათ, ხოლო ბილდი ვერდება, თუ ისინი შეიცვალა და ცვლილებები არავინ დაამტკიცა. ლოკალური გაშვებები არაფერს ტვირთავს, რადგან ისინი ატვირთავდნენ კომიტის გარეშე დარჩენილ ცვლილებებს. გადაეცით `-Ptuist.snapshots=false`, რათა CI-ში ატვირთვა გამორთოთ.

Paparazzi-ს და Roborazzi-ს ჩაწერის ტასკები, მაგალითად `recordPaparazziDebug`, ყოველთვის ტვირთავენ მონაცემებს, როცა სნეპშოტები ჩართულია.

## პარამეტრები {#options}

ბლოკი `snapshots` იღებს შემდეგ პარამეტრებს:

- `enabled`: ტვირთავს თუ არა სნეპშოტებს. ნაგულისხმევი მნიშვნელობაა `false`.
- `set`: სიმრავლე, რომლის ფარგლებშიც ხდება ბილდების შედარება. ნაგულისხმევად იყენებს Gradle პროექტის გზას.
- `directory`: საქაღალდე ასატვირთი გამოსახულებებით, Gradle პროექტის მიმართ. ნაგულისხმევად იყენებს იმ ადგილს, სადაც გენერირებული პრივიუ ტესტი ან სნეპშოტ ბიბლიოთეკა წერს მონაცემებს.
- `failOnChanges`: ვერდება თუ არა ბილდი, თუ ცვლილებები არავინ დაამტკიცა. ნაგულისხმევი მნიშვნელობაა `true`.
- `diffThreshold`: პიქსელების წილი 0-დან 1-მდე, რომელიც შეიძლება განსხვავდებოდეს, სანამ გამოსახულება შეცვლილად ჩაითვლება. ნაგულისხმევი მნიშვნელობაა `0`.
- `previews { generateTests }`: გენერირდება თუ არა Compose პრივიუ ტესტი. ნაგულისხმევი მნიშვნელობაა `true`.
- `previews { packageTrees }`: პაკეტები, რომლებშიც ეძებენ პრივიუებს. ნაგულისხმევად იყენებს Android ნეიმსფეისს.
- `previews { includePrivatePreviews }`: რენდერდება თუ არა ასევე კერძო `@Preview` ფუნქციები. ნაგულისხმევი მნიშვნელობაა `false`.
- `previews { theme }`: Android თემა, რომელშიც რენდერდება პრივიუები. ნაგულისხმევად იყენებს Paparazzi-ს თემას.
