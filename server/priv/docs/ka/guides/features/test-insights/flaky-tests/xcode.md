---
{
  "title": "Xcode-ის არასტაბილური ტესტები",
  "titleTemplate": ":title · არასტაბილური ტესტები · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Xcode-ის პროექტებში Tuist-ით."
}
---
# Xcode-ის არასტაბილური ტესტები {#xcode-flaky-tests}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ინსაიტები</.localized_link> კონფიგურირებული. Tuist ავლენს არასტაბილურ ტესტებს ყოველი ტესტების გაშვების მიერ ატვირთული ტესტ-ინსაიტის მოვლენებიდან.

<!-- @snippet: ./_intro -->

![არასტაბილური ტესტების გვერდი](/images/guides/features/test-insights/flaky-tests-page.png)

## როგორ მუშაობს არასტაბილურობის აღმოჩენა {#how-it-works}

Tuist ავლენს არასტაბილურ ტესტებს ორი გზით:

### ტესტების ხელახალი გაშვება {#test-retries}

როდესაც ტესტებს გაუშვებთ ხელახალი გაშვების ფუნქციით, Tuist აანალიზებს თითოეული ცდის შედეგებს. თუ ტესტი ზოგიერთ ცდაზე ჩავარდება, მაგრამ სხვებზე წარმატებით დასრულდება, ის მონიშნული იქნება როგორც არასტაბილური.

გადაეცით `-retry-tests-on-failure` ან `-test-iterations` `tuist xcodebuild test`-ის მეშვეობით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![არასტაბილური სატესტო შემთხვევის დეტალები](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## არასტაბილური ტესტების კარანტინში მოთავსება {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

კარანტინში მოთავსებული ტესტი ერთ-ერთ რეჟიმშია:

- **ჩუმად**: ტესტი მაინც გაეშვება, მაგრამ `tuist xcodebuild test` ნიღბავს შეცდომას. შეცდომები კვლავ ამარაგებენ არასტაბილური ტესტების დეტექტორს, ასე რომ შეგიძლიათ აკვირდეთ ტესტს ბილდის გაწყვეტის გარეშე. აირჩიეთ ეს იმ ტესტისთვის, რომელსაც აქტიურად იკვლევთ.
- **გამოტოვებული**: xcodebuild იღებს `-skip-testing <identifier>`, ამიტომ ტესტი არასდროს იწყება. ის არ წარმოქმნის ახალ შედეგებს და ქრება არასტაბილური ტესტების დაფიდან მის ხელახლა ჩართვამდე. აირჩიეთ ეს, როდესაც ტესტი გაფუჭებულია, ნელია ან იმდენად მუდმივად არასტაბილურია, რომ მისი გაშვება უბრალოდ CI-ის წუთების ფლანგვაა.

<!-- @snippet: ./_quarantined-passing -->

### ტესტების გაშვება {#running-tests}

`tuist xcodebuild test` არის პასსთრაუპ გარსი, რომელიც ავტომატურად ითვალისწინებს ორივე რეჟიმს. გამოიყენეთ ის ისე, როგორც xcodebuild-ს გამოიძახებდით:

```sh
tuist xcodebuild test -scheme MyScheme
```

გამოტოვებული ტესტები ემატება თქვენს xcodebuild-ის გამოძახებას როგორც `-skip-testing <identifier>` და არასდროს იწყება. ჩუმად მოთავსებული ტესტები ჩვეულებრივად გაეშვება; თუ ისინი ჩავარდებიან, შეცდომა ნიღბავდება მიღებულ ბილდის სტატუსში.

#### კარანტინის გვერდის ავლა {#bypassing-quarantine}

`tuist xcodebuild test` იღებს `--skip-quarantine`-ს ყველაფრის გასაშვებად, ჩუმად მოთავსებული და გამოტოვებული ტესტების ჩათვლით:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild-ის პირდაპირ გამოძახება {#calling-xcodebuild-directly}

თუ `tuist xcodebuild test`-ის გავლა არ შეგიძლიათ, თავად გააფართოვეთ კარანტინში მოთავსებული ტესტები `-skip-testing` არგუმენტებად `tuist test case list`-ის მეშვეობით:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

ეს არის უსაფრთხო ნაგულისხმევი ქცევა `tuist xcodebuild test`-ის გარეთ: ჩუმად მოთავსებული ტესტებისთვის შეცდომების ნიღბავ ხდება მხოლოდ მაშინ, როდესაც ამ ბრძანებას გაივლით, ამიტომ ორივე რეჟიმის გამოტოვება თავიდან აგაცილებთ ცრუ CI-ის შეცდომებს. თუ უფრო ზუსტი კონტროლი გჭირდებათ, გაიარეთ `tuist xcodebuild test`-ის გავლა.

## ახალი ტესტების სტრეს-ტესტირება {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

სატესტო შემთხვევა ითვლება ახლად, თუ ის ბოლო 90 დღის განმავლობაში არ გაშვებულა CI-ში პროექტის ნაგულისხმევ შტოზე, ან კომიტზე, რომელიც მას შემდეგ შევიდა მასში. მერჯის რიგით, რიგის მიერ გაშვებული სატესტო შემთხვევა ცნობილი ხდება მას შემდეგ, რაც რიგის კომიტი შევა, და რჩება ახალი, თუ რიგი მას ჩამოაგდებს. კომიტები შეესაბამება <.localized_link href="/guides/features/test-insights/xcode#git-history">Git-ის ისტორიას</.localized_link>, რომელსაც Tuist აგროვებს CI-ზე.

<!-- @snippet: ./_stress-modes -->

გადაეცით ის პასსთრაუპ არგუმენტებამდე, ან დააყენეთ `TUIST_TEST_STRESS_NEW_TESTS` რეჟიმის შესაცვლელად თითოეული CI-ის არხისთვის:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

ხელახალი გაშვებები იყენებენ იმას, რაც პირველმა გაშვებამ ააგო.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
