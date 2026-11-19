---
{
  "title": "არასტაბილური ტესტები Xcode-ში",
  "titleTemplate": ":title · არასტაბილური ტესტები · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Xcode პროექტებში Tuist-ის საშუალებით."
}
---
# Xcode-ის არასტაბილური ტესტები {#xcode-flaky-tests}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ანალიტიკა</.localized_link> კონფიგურირებული. Tuist აღმოაჩენს არასტაბილურ ტესტებს ყოველი ტესტების გაშვების მიერ ატვირთული ტესტ-ინსაიტების მოვლენებიდან.

<!-- @snippet: ./_intro -->

![არასტაბილური ტესტების გვერდი](/images/guides/features/test-insights/flaky-tests-page.png)

## როგორ მუშაობს არასტაბილურობის აღმოჩენა {#how-it-works}

Tuist აღმოაჩენს არასტაბილურ ტესტებს ორი გზით:

### ტესტების ხელახლა გაშვება {#test-retries}

როდესაც ტესტებს ხელახლა გაშვების ფუნქციით აწარმოებთ, Tuist აანალიზებს თითოეული მცდელობის შედეგებს. თუ ტესტი ზოგიერთ მცდელობაზე ვერდება, მაგრამ სხვებზე გადის, ის არასტაბილურად ინიშნება.

გადაეცით `-retry-tests-on-failure` ან `-test-iterations` ბრძანების `tuist xcodebuild test` მეშვეობით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![არასტაბილური სატესტო შემთხვევის დეტალები](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## არასტაბილური ტესტების კარანტინში მოქცევა {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

კარანტინში მოქცეული ტესტი ერთ-ერთ რეჟიმშია:

- **ჩახშობილი**: ტესტი მაინც გაეშვება, მაგრამ `tuist xcodebuild test` ნიღბავს შეცდომას. შეცდომები მაინც ამარაგებენ არასტაბილური ტესტების დეტექტორს, ასე რომ შეგიძლიათ დააკვირდეთ ტესტს ბილდის გაწყვეტის გარეშე. აირჩიეთ ეს იმ ტესტისთვის, რომელსაც აქტიურად იკვლევთ.
- **გამოტოვებული**: xcodebuild იღებს `-skip-testing <identifier>`, ამიტომ ტესტი არასდროს იწყება. ის არ წარმოქმნის ახალ შედეგებს და ქრება არასტაბილური ტესტების დაშბორდიდან, სანამ ხელახლა არ ჩართავთ. აირჩიეთ ეს, როცა ტესტი გაუმართავია, ნელია, ან იმდენად მუდმივად არასტაბილურია, რომ მისი გაშვება უბრალოდ CI-ის წუთების ფლანგვაა.

<!-- @snippet: ./_quarantined-passing -->

### ტესტების გაშვება {#running-tests}

`tuist xcodebuild test` არის პასთრუ რაპერი, რომელიც ავტომატურად ითვალისწინებს ორივე რეჟიმს. გამოიყენეთ ის ისე, როგორც xcodebuild-ს გამოიძახებდით:

```sh
tuist xcodebuild test -scheme MyScheme
```

გამოტოვებული ტესტები ემატება თქვენს xcodebuild-ის გამოძახებას როგორც `-skip-testing <identifier>` და არასდროს იწყება. ჩახშობილი ტესტები ჩვეულებრივად გაეშვება; თუ ისინი ვერდებიან, შეცდომა ინიღბება მიღებულ ბილდის სტატუსში.

#### კარანტინის გვერდის ავლა {#bypassing-quarantine}

`tuist xcodebuild test` იღებს `--skip-quarantine` ყველაფრის გასაშვებად, ჩახშობილი და გამოტოვებული ტესტების ჩათვლით:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild-ის პირდაპირ გამოძახება {#calling-xcodebuild-directly}

თუ `tuist xcodebuild test`-ის გამოყენება არ შეგიძლიათ, თავად გაშალეთ კარანტინში მოქცეული ტესტები `-skip-testing` არგუმენტებად `tuist test case list`-ის მეშვეობით:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

ეს არის უსაფრთხო ნაგულისხმევი `tuist xcodebuild test`-ის გარეთ: ჩახშობილი ტესტებისთვის შეცდომების ნიღბავ მხოლოდ მაშინ ხდება, როცა ამ ბრძანების მეშვეობით გადიხართ, ამიტომ ორივე რეჟიმის გამოტოვება თავიდან აიცილებს ცრუ CI-ის ვერდებს. თუ უფრო ზუსტი კონტროლი გჭირდებათ, გადადით `tuist xcodebuild test`-ის მეშვეობით.

## ახალი ტესტების სტრეს-ტესტირება {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

სატესტო შემთხვევა ახლად ითვლება, თუ ის ბოლო 90 დღის განმავლობაში არ გაშვებულა CI-ზე პროექტის ნაგულისხმევ შტოზე, ან კომიტზე, რომელიც შემდგომში მასზე მოხვდა. შერწყმის რიგით, რიგის მიერ გაშვებული სატესტო შემთხვევა ცნობილი ხდება, როცა რიგის კომიტი მოხვდება შტოზე, და რჩება ახალი, თუ რიგი მას ტოვებს. კომიტები შეესაბამება <.localized_link href="/guides/features/test-insights/xcode#git-history">Git-ის ისტორიას</.localized_link>, რომელსაც Tuist აგროვებს CI-ზე.

<!-- @snippet: ./_stress-modes -->

გადაეცით ის პასთრუ არგუმენტებამდე, ან დააყენეთ `TUIST_TEST_STRESS_NEW_TESTS` რეჟიმის CI-ის თითოეული არხისთვის შესაცვლელად:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

ხელახლა გაშვებები იყენებენ იმას, რაც პირველმა გაშვებამ ააგო.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
