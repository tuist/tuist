---
{
  "title": "Xcode-ის კოდის დაფარვა",
  "titleTemplate": ":title · კოდის დაფარვა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ატვირთეთ Xcode პროექტების კოდის დაფარვის მონაცემები Tuist-ში და თვალყური ადევნეთ მას ფაილებისა და კომიტების მიხედვით."
}
---
# Xcode-ის კოდის დაფარვა {#xcode-code-coverage}

კოდის დაფარვა გაჩვენებთ, თქვენი ტესტების მიერ შესრულებულ კოდის ხაზებს. Tuist ატვირთავს ყოველი ტესტების გაშვების ხაზოვან დაფარვას და აერთიანებს ერთი კომიტის გაშვებებს ერთ მაჩვენებლად — პროექტის, თითოეული target-ისა და თითოეული ფაილისთვის. დაშბორდის **კოდის დაფარვის** გვერდი აჩვენებს მას კომიტების მიხედვით და როგორც ტრენდს თითოეული branch-ისთვის.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> თუ თქვენს პროექტს Tuist-ით აგენერირებთ, მიჰყევით <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">გენერირებული პროექტის სახელმძღვანელოს</.localized_link>: ის ზომავს ბინარული ქეშიდან მოსულ კოდს და ინარჩუნებს იმ test target-ების დაფარვას, რომლებსაც შერჩევითი ტესტირება გამოტოვებს.

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

`TUIST_COVERAGE_UPLOAD` გარემოს ცვლადი (`1` ან `0`) უპირატესობას იღებს პარამეტრზე, მაგალითად, ატვირთვის გამოსართავად ისეთ jobs-ში, რომლებიც ასრულებენ pull request-ებს fork-ებიდან.

შემდეგ ჩართეთ **კოდის დაფარვა** თქვენი scheme-ის test action-ში (**Edit Scheme › Test › Options**), ან გადაეცით `-enableCodeCoverage YES` გაშვებას და გაუშვით ტესტები `tuist xcodebuild test`-ით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist ატვირთავს გაშვების მიერ შეგროვებულ დაფარვას ტესტის შედეგებთან ერთად.

### CI-ზე თითოეული კომიტის დასრულება {#complete-each-commit}

კომიტის დაფარვა ხშირად რამდენიმე job-ისგან მოდის: ერთი თითოეული scheme-ის, shard-ის ან პლატფორმისთვის. Tuist ვერ განსაზღვრავს, როდის მოახსენა ბოლომ მათგან, ამიტომ მიუთითეთ ეს. როგორც კი კომიტის ყველა test job დასრულდება, გაუშვით ეს job-ში, რომელიც დამოკიდებულია მათ ყველაზე:

```sh
tuist coverage complete
```

სანამ კომიტი არ დასრულდება, მისი დაფარვა ჩანს როგორც **მიმდინარე** და არ შედის მისი branch-ის ტრენდში. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">გენერირებული პროექტის სახელმძღვანელო</.localized_link> აღწერს თითოეულ სტატუსს.

## გამოტოვებული ტესტები {#skipped-tests}

როდესაც გაშვება ტესტებს გამოტოვებს `-skip-testing`-ით, ის ზომავს ნაკლებს, ვიდრე კომიტის ტესტები ფარავს, და Tuist ვერ გადააქვს ეს ტესტები წინა გაშვებიდან. კომიტის დაფარვა არის **არასრული**, თუ კომიტზე სხვა გაშვებამ არ გაუშვა ისინი. კომიტის სისრულის შესანარჩუნებლად, გაუშვით ყოველი ტესტი კომიტზე მინიმუმ ერთ გაშვებაში.

ტესტები, რომლებსაც quarantine გამოტოვებს, საერთოდ არ შედის დაფარვაში, ამიტომ ისინი არასდროს ხდიან კომიტს **არასრულს**.

## წარმადობაზე გავლენა {#performance-impact}

დაფარვის შეგროვება მატებს დამატებით დატვირთვას, ძირითადად ტესტების დასრულების შემდეგ, როდესაც Xcode წერს თავის დაფარვის ანგარიშს და Tuist ექსპორტავს დაფარვას. ტესტების აგება და გაშვება დაახლოებით იმდენსვე ხანს გრძელდება, როგორც მის გარეშე.

## დაფარვის მოთხოვნა {#querying}

`tuist coverage` ბრძანებები კითხულობენ იმას, რასაც დაშბორდი აჩვენებს. `--commit`-ის გარეშე, ისინი კითხულობენ `--branch`-ის ან თქვენი ნაგულისხმევი branch-ის უახლეს სრულ კომიტს:

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
