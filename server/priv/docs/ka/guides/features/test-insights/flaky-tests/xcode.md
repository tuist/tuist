---
{
  "title": "არასტაბილური ტესტები Xcode-ში",
  "titleTemplate": ":title · არასტაბილური ტესტები · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Xcode-ის პროექტებში Tuist-ით."
}
---
# Xcode-ის არასტაბილური ტესტები {#xcode-flaky-tests}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ინსაიტები</.localized_link> კონფიგურირებული. Tuist აღმოაჩენს არასტაბილურ ტესტებს ყოველი ტესტების გაშვების მიერ ატვირთული ტესტ-ინსაიტის მოვლენებიდან.

<!-- @snippet: ./_intro -->

![არასტაბილური ტესტების გვერდი](/images/guides/features/test-insights/flaky-tests-page.png)

## როგორ მუშაობს არასტაბილურობის აღმოჩენა {#how-it-works}

Tuist აღმოაჩენს არასტაბილურ ტესტებს ორი გზით:

### ტესტების ხელახლა ცდა {#test-retries}

როდესაც ტესტებს ცდის ფუნქციონალით ასრულებთ, Tuist აანალიზებს თითოეული ცდის შედეგებს. თუ ტესტი ზოგიერთ ცდაზე ვერდება, მაგრამ სხვებზე გადის, ის მონიშნულია როგორც არასტაბილური.

გაატარეთ `-retry-tests-on-failure` ან `-test-iterations` `tuist xcodebuild test`-ის მეშვეობით:

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

- **ჩუმად დატოვებული**: ტესტი მაინც სრულდება, მაგრამ `tuist xcodebuild test` ფარავს შეცდომას. შეცდომები კვლავ კვებავენ არასტაბილური ტესტების დეტექტორს, ასე რომ, შეგიძლიათ აკვირდეთ ტესტს ბილდის გაწყვეტის გარეშე. აირჩიეთ ეს იმ ტესტისთვის, რომელსაც აქტიურად იკვლევთ.
- **გამოტოვებული**: xcodebuild იღებს `-skip-testing <identifier>`, ამიტომ ტესტი არასდროს იწყება. ის არ წარმოქმნის ახალ შედეგებს და ქრება არასტაბილური ტესტების დაშბორდიდან მის ხელახლა ჩართვამდე. აირჩიეთ ეს, როდესაც ტესტი გაუმართავია, ნელია, ან იმდენად მუდმივად არასტაბილურია, რომ მისი გაშვება უბრალოდ CI-ის წუთების ფლანგვაა.

<!-- @snippet: ./_quarantined-passing -->

### ტესტების გაშვება {#running-tests}

`tuist xcodebuild test` არის პასსთრაუ გარსი, რომელიც ავტომატურად ითვალისწინებს ორივე რეჟიმს. გამოიყენეთ ის ისევე, როგორც xcodebuild-ს გამოიძახებდით:

```sh
tuist xcodebuild test -scheme MyScheme
```

გამოტოვებული ტესტები ემატება თქვენს xcodebuild-ის გამოძახებას როგორც `-skip-testing <identifier>` და არასდროს იწყება. ჩუმად დატოვებული ტესტები ჩვეულებრივად სრულდება; თუ ისინი ვერდება, შეცდომა იფარება მიღებულ ბილდის სტატუსში.

#### კარანტინის გვერდის ავლა {#bypassing-quarantine}

`tuist xcodebuild test` იღებს `--skip-quarantine`-ს ყველაფრის გასაშვებად, ჩუმად დატოვებული და გამოტოვებული ტესტების ჩათვლით:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild-ის პირდაპირ გამოძახება {#calling-xcodebuild-directly}

თუ `tuist xcodebuild test`-ის გავლა არ შეგიძლიათ, თავად გააფართოვეთ კარანტინში მოქცეული ტესტები `-skip-testing` არგუმენტებად `tuist test case list`-ის მეშვეობით:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

ეს არის უსაფრთხო ნაგულისხმევი `tuist xcodebuild test`-ის გარეთ: ჩუმად დატოვებული ტესტების შეცდომების დაფარვა ხდება მხოლოდ მაშინ, როდესაც ამ ბრძანების გავლით მოქმედებთ, ამიტომ ორივე რეჟიმის გამოტოვება თავიდან აიცილებს ცრუ CI-ის შეცდომებს. თუ უფრო ზუსტი კონტროლი გჭირდებათ, გამოიყენეთ `tuist xcodebuild test`.

## ახალი ტესტების სტრეს-ტესტირება {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

სატესტო შემთხვევა ითვლება ახლად, თუ ის ბოლო 90 დღის განმავლობაში არ გაშვებულა CI-ზე პროექტის ნაგულისხმევ შტოზე, ან კომიტზე, რომელიც მასზე შემდგომში მოხვდა. მერჯის რიგით, ტესტის შემთხვევა, რომელიც რიგმა გაუშვა, ცნობილი ხდება მას შემდეგ, რაც რიგის კომიტი მოხვდება შტოზე, და რჩება ახლად, თუ რიგი მას ტოვებს. კომიტები შეესაბამება <.localized_link href="/guides/features/test-insights/xcode#git-history">Git-ის ისტორიას</.localized_link>, რომელსაც Tuist აგროვებს CI-ზე.

<!-- @snippet: ./_stress-modes -->

გაატარეთ ის პასსთრაუ არგუმენტებამდე, ან დააყენეთ `TUIST_TEST_STRESS_NEW_TESTS` რეჟიმის CI-ის თითოეული არხისთვის ვარიაციისთვის:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

ხელახლა გაშვებები იყენებენ იმას, რაც პირველმა გაშვებამ ააგო.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
