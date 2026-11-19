---
{
  "title": "Xcode-ის კოდის დაფარვა",
  "titleTemplate": ":title · კოდის დაფარვა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ატვირთეთ Xcode პროექტების კოდის დაფარვის მონაცემები Tuist-ზე და მიჰყევით მათ ფაილებისა და კომიტების მიხედვით."
}
---
# Xcode-ის კოდის დაფარვა {#xcode-code-coverage}

კოდის დაფარვა გაჩვენებთ, თქვენი ტესტები კოდის რომელ ხაზებს ასრულებენ. Tuist ატვირთავს ყოველი ტესტების გაშვების ხაზოვან დაფარვას და კომიტის გაშვებებს ერთ რიცხვად აჯამებს — პროექტის, თითოეული სამიზნისა და თითოეული ფაილის მიხედვით. დაშბორდის **Code Coverage** გვერდი მას კომიტის მიხედვით და თითოეული შტოს ტრენდის სახით აჩვენებს.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> თუ პროექტს Tuist-ით გენერირებთ, მიჰყევით <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">გენერირებული პროექტის სახელმძღვანელოს</.localized_link>: ის ზომავს ბინარული ქეშიდან მოსულ კოდს და ინარჩუნებს იმ ტესტის სამიზნეების დაფარვას, რომლებსაც შერჩევითი ტესტირება ტოვებს.

## მოწყობა {#setup}

### დაფარვის შეგროვება {#collect-coverage}

ჩართეთ დაფარვის ატვირთვა თქვენს `Tuist.swift`-ში. ნაგულისხმევად ის გამორთულია:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` გარემოს ცვლადი (`1` ან `0`) უპირატესობას იღებს პარამეტრზე, მაგალითად, იმ ჯობებში ატვირთვის გამოსართავად, რომლებიც ფორკებიდან pull request-ებს ასრულებენ.

შემდეგ ჩართეთ **Code Coverage** თქვენი სქემის ტესტის მოქმედებაში (**Edit Scheme › Test › Options**), ან გადაეცით `-enableCodeCoverage YES` გაშვებას და გაუშვით ტესტები `tuist xcodebuild test`-ის მეშვეობით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist ატვირთავს გაშვების მიერ შეგროვებულ დაფარვას ტესტის შედეგებთან ერთად.

### CI-ზე თითოეული კომიტის დასრულება {#complete-each-commit}

კომიტის დაფარვა ხშირად რამდენიმე ჯობიდან მოდის: ერთი თითოეული სქემის, შარდის ან პლატფორმის მიხედვით. Tuist ვერ განსაზღვრავს, როდის მოახსენებს ბოლო მათგანი, ამიტომ მიუთითეთ ეს. როგორც კი კომიტის ყველა ტესტის ჯობი დასრულდება, გაუშვით ეს ჯობაში, რომელიც ყველა მათგანზეა დამოკიდებული:

```sh
tuist coverage complete
```

სანამ კომიტი არ დასრულდება, მისი დაფარვა ჩანს როგორც **In progress** და არ შედის მისი შტოს ტრენდში. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">გენერირებული პროექტის სახელმძღვანელო</.localized_link> აღწერს თითოეულ სტატუსს.

## გამოტოვებული ტესტები {#skipped-tests}

როდესაც გაშვება ტესტებს `-skip-testing`-ით ტოვებს, ის ზომავს ნაკლებს, ვიდრე კომიტის ტესტები ფარავენ, და Tuist ვერ გადააქვს ეს ტესტები წინა გაშვებიდან. კომიტის დაფარვა არის **Incomplete**, თუ კომიტზე სხვა გაშვებამ ისინი არ გაუშვა. კომიტის სრულყოფილობის შესანარჩუნებლად, თითოეულ კომიტზე მინიმუმ ერთ გაშვებაში ყველა ტესტი გაუშვით.

ტესტები, რომლებსაც კარანტინი ტოვებს, საერთოდ არ შედიან დაფარვაში, ამიტომ ისინი არასდროს ხდიან კომიტს **Incomplete**.

## წარმადობაზე გავლენა {#performance-impact}

დაფარვის შეგროვება დამატებით დატვირთვას ქმნის, ძირითადად ტესტების დასრულების შემდეგ, როდესაც Xcode წერს თავის დაფარვის ანგარიშს და Tuist ექსპორტავს დაფარვას. ტესტების აგება და გაშვება დაახლოებით იმდენსვე დროს იღებს, რამდენსაც მის გარეშე.

## დაფარვის მოთხოვნა {#querying}

`tuist coverage` ბრძანებები კითხულობენ იმას, რასაც დაშბორდი აჩვენებს. `--commit`-ის გარეშე, ისინი კითხულობენ `--branch`-ის უახლეს სრულ კომიტს, ან თქვენს ნაგულისხმევ შტოს:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

ტესტის გაშვების საკუთარი დაფარვა ჩანს `tuist test show <test-run-id>`-ში.

ყველა მათგანი იღებს `--json`-ს სკრიპტინგისთვის.
