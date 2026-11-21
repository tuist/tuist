---
{
  "title": "Xcode-ის კოდის დაფარვა",
  "titleTemplate": ":title · კოდის დაფარვა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ატვირთეთ Xcode-ის პროექტების კოდის დაფარვის მონაცემები Tuist-ში და მიჰყევით მათ ფაილებისა და კომიტების მიხედვით."
}
---
# Xcode-ის კოდის დაფარვა {#xcode-code-coverage}

კოდის დაფარვა გაჩვენებთ, თქვენი ტესტები კოდის რომელ ხაზებს ასრულებდნენ. Tuist ატვირთავს ყოველი ტესტების გაშვების ხაზობრივ დაფარვას და კომიტის გაშვებებს ერთ მაჩვენებლად აერთიანებს — პროექტისთვის, თითოეული მიზნისა და ფაილისთვის. დაფის **კოდის დაფარვის** გვერდი მას კომიტების მიხედვით და თითოეული შტოს ტრენდის სახით აჩვენებს.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> თუ პროექტს Tuist-ით გენერირებთ, ნაცვლად ამისა მიჰყევით <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">გენერირებული პროექტის სახელმძღვანელოს</.localized_link>: ის ზომავს ბინარული ქეშიდან მოსულ კოდს და ინარჩუნებს იმ სატესტო მიზნების დაფარვას, რომლებსაც შერჩევითი ტესტირება ტოვებს.

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

`TUIST_COVERAGE_UPLOAD` გარემოს ცვლადი (`1` ან `0`) უპირატესობას იღებს პარამეტრზე, მაგალითად, ატვირთვის გამოსართავად ჯობებში, რომლებიც ფორკებიდან შემოსულ pull request-ებს ასრულებენ.

შემდეგ ჩართეთ **კოდის დაფარვა** თქვენი სქემის სატესტო მოქმედებაში (**Edit Scheme › Test › Options**), ან გადაეცით `-enableCodeCoverage YES` გაშვებას და გაუშვით ტესტები `tuist xcodebuild test`-ის მეშვეობით:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist ატვირთავს გაშვების მიერ შეგროვებულ დაფარვას მის სატესტო შედეგებთან ერთად.

### CI-ზე თითოეული კომიტის დასრულება {#complete-each-commit}

კომიტის დაფარვა ხშირად რამდენიმე ჯობიდან მოდის: ერთი თითოეული სქემის, შარდის ან პლატფორმისთვის. Tuist ვერ განსაზღვრავს, როდის ანგარიშგებს ბოლო მათგანი, ამიტომ მიუთითეთ ეს. როგორც კი კომიტის ყველა სატესტო ჯობი დასრულდება, გაუშვით ეს ჯობაში, რომელიც ყველა მათგანზეა დამოკიდებული:

```sh
tuist coverage complete
```

ბრძანება კითხულობს კომიტს ჩექაუთის `HEAD`-დან, ანუ იმ კომიტს, რომელზეც თქვენი ტესტები გაშვებული იყო; სხვა კომიტის მითითებისთვის გადაეცით `--commit <sha>`. სანამ კომიტი არ დასრულდება, მისი დაფარვა ჩანს როგორც **მიმდინარე** და არ შედის მისი შტოს ტრენდში. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">გენერირებული პროექტის სახელმძღვანელო</.localized_link> აღწერს თითოეულ სტატუსს.

## გამოტოვებული ტესტები {#skipped-tests}

როდესაც გაშვება ტოვებს ტესტებს `-skip-testing`-ის მეშვეობით, ის ზომავს ნაკლებს, ვიდრე კომიტის ტესტები ფარავენ, და Tuist ვერ გადაიტანს ამ ტესტებს წინა გაშვებიდან. კომიტის დაფარვა არის **არასრული**, თუ კომიტზე სხვა გაშვებამ ისინი არ გაუშვა. კომიტის სისრულის შესანარჩუნებლად, გაუშვით ყოველი ტესტი კომიტზე სულ მცირე ერთ გაშვებაში.

ტესტები, რომლებსაც კარანტინი ტოვებს, საერთოდ არ შედიან დაფარვაში, ამიტომ ისინი არასდროს ხდიან კომიტს **არასრულად**.

## გავლენა წარმადობაზე {#performance-impact}

დაფარვის შეგროვება ზრდის დამატებით დატვირთვას, ძირითადად ტესტების დასრულების შემდეგ, როდესაც Xcode წერს თავის დაფარვის ანგარიშს და Tuist ექსპორტავს დაფარვას. ტესტების აგება და გაშვება დაახლოებით იმავე დროს იკავებს, რაც მის გარეშე.

## დაფარვის მოთხოვნა {#querying}

`tuist coverage` ბრძანებები კითხულობენ იმას, რასაც დაფა აჩვენებს. `--commit`-ის გარეშე, ისინი კითხულობენ `--branch`-ის უახლეს სრულ კომიტს, ან თქვენს ნაგულისხმევ შტოს:

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
