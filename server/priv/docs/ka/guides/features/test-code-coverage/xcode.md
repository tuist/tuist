---
{
  "title": "Xcode-ის კოდის დაფარვა",
  "titleTemplate": ":title · კოდის დაფარვა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ატვირთეთ Xcode პროექტების კოდის დაფარვის მონაცემები Tuist-ში და მიჰყევით მათ ფაილებისა და კომიტების მიხედვით."
}
---
# Xcode-ის კოდის დაფარვა {#xcode-code-coverage}

კოდის დაფარვა გიჩვენებს, თქვენი ტესტები კოდის რომელ ხაზებს ასრულებენ. Tuist ატვირთავს ყოველი ტესტების გაშვების ხაზოვან დაფარვას და აერთიანებს ერთი კომიტის გაშვებებს ერთ მაჩვენებლად — პროექტისთვის, თითოეული მიზნისთვის და თითოეული ფაილისთვის. ინსტრუმენტების პანელის **კოდის დაფარვის** გვერდი აჩვენებს მას კომიტების მიხედვით და როგორც ტრენდს თითოეული შტოსთვის.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> თუ პროექტს Tuist-ით გენერირებთ, მიჰყევით <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">გენერირებული პროექტის სახელმძღვანელოს</.localized_link>: ის ზომავს ბინარული ქეშიდან მომავალ კოდს და ინარჩუნებს იმ სატესტო მიზნების დაფარვას, რომლებსაც შერჩევითი ტესტირება გამოტოვებს.

## მოწყობა {#setup}

### დაფარვის შეგროვება {#collect-coverage}

ჩართეთ კოდის დაფარვის ატვირთვა თქვენს `Tuist.swift`-ში. ის ნაგულისხმევად გამორთულია:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` გარემოს ცვლადს (`1` ან `0`) აქვს უპირატესობა პარამეტრთან შედარებით, მაგალითად, ატვირთვის გამოსართავად ამოღებებიდან (forks) მომავალი pull request-ების შემსრულებელ დავალებებში.

შემდეგ ჩართეთ **კოდის დაფარვა** თქვენი სქემის სატესტო ქმედებაში (**Edit Scheme › Test › Options**), ან გადაეცით `-enableCodeCoverage YES` გაშვებისას და გაუშვით ტესტები `tuist xcodebuild test`-ის მეშვეობით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist ატვირთავს გაშვების მიერ შეგროვებულ დაფარვას ტესტის შედეგებთან ერთად.

### CI-ზე თითოეული კომიტის დასრულება {#complete-each-commit}

კომიტის დაფარვა ხშირად რამდენიმე დავალებიდან მოდის: ერთი თითოეული სქემის, შარდის ან პლატფორმისთვის. Tuist-მა არ იცის, როდის ანგარიშდება ბოლო მათგანი, ამიტომ მიუთითეთ ეს. როგორც კი კომიტის ყველა სატესტო დავალება დასრულდება, გაუშვით ეს დავალება, რომელიც ყველა მათგანზეა დამოკიდებული:

```sh
tuist coverage complete
```

სანამ კომიტი არ დასრულდება, მისი დაფარვა ჩანს როგორც **მიმდინარე** და არ შედის მისი შტოს ტრენდში. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">გენერირებული პროექტის სახელმძღვანელო</.localized_link> აღწერს თითოეულ სტატუსს.

## გამოტოვებული ტესტები {#skipped-tests}

როდესაც გაშვება ტესტებს `-skip-testing`-ით გამოტოვებს, ის ზომავს ნაკლებს, ვიდრე კომიტის ტესტები ფარავენ, და Tuist ვერ გადააქვს ეს ტესტები წინა გაშვებიდან. კომიტის დაფარვა არის **არასრული**, თუ კომიტზე სხვა გაშვებამ ისინი არ გაუშვა. კომიტის სისრულის შესანარჩუნებლად, გაუშვით ყოველი ტესტი კომიტზე მინიმუმ ერთ გაშვებაში.

ტესტები, რომლებსაც კარანტინი გამოტოვებს, საერთოდ არ შედიან დაფარვაში, ამიტომ ისინი არასდროს ხდიან კომიტს **არასრულად**.

## წარმადობაზე გავლენა {#performance-impact}

დაფარვის შეგროვება ზრდის დატვირთვას, ძირითადად ტესტების დასრულების შემდეგ, როცა Xcode წერს თავის დაფარვის ანგარიშს და Tuist ექსპორტავს დაფარვას. ტესტების აგება და გაშვება დაახლოებით იმდენს ხანს გრძელდება, რამდენსაც მის გარეშე.

## დაფარვის მოთხოვნა {#querying}

`tuist coverage` ბრძანებები კითხულობენ იმას, რასაც ინსტრუმენტების პანელი აჩვენებს. `--commit`-ის გარეშე, ისინი კითხულობენ `--branch`-ის ან თქვენი ნაგულისხმევი შტოს უახლეს სრულ კომიტს:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

ტესტების გაშვების საკუთარი დაფარვა ჩანს `tuist test show <test-run-id>`-ში.

ყველა მათგანი იღებს `--json`-ს სკრიპტინგისთვის.
