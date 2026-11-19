---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · რანერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions ჯობი Tuist რანერებზე: დააკავშირეთ GitHub, მიუთითეთ runs-on-ზე Tuist პროფილი და დააკვირდით მას დაშბორდში."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

ამოცანის ფლოტზე გასაშვებად სამი ცვლილებაა საჭირო: დააკავშირეთ GitHub, მიმართეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილს</.localized_link> და შეასრულეთ push.

1. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` მოვლენებს ამ ორგანიზაციისთვის და ანაწილებს შესაბამის ამოცანებს ფლოტზე. ამ კავშირის გარეშე, არცერთი ამოცანა ვერ მიაღწევს თქვენს რანერებს.
2. **მიმართეთ `runs-on` Tuist-ის პროფილს.** ყოველი აქტიური ანგარიში იწყება ორი გამოსაყენებელი <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **აირჩიეთ Xcode რანერის პროფილით**
   >
   > macOS რანერის იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს ამოცანის დაწყებამდე პროფილის მიხედვით. თუ გადადიხართ GitHub-ზე განთავსებული რანერებიდან, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და ქმედებებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად ეხება Xcode-ის ინსტალაციებს, რომლებიც სპეციფიკურია GitHub-ზე განთავსებული იმიჯებისთვის და შეიძლება ჩავარდეს Tuist Runners-ზე.
   >
   > სხვა Xcode ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun`, და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს workflow-ში დამატებითი კონფიგურაციის გარეშე.

3. **შეასრულეთ push და დააკვირდით.** ამოცანა დგება რიგში, იკავებს რანერი და ნაკადი ბრუნდება თქვენი Tuist დაშბორდის **რანერების** სექციაში, სადაც შეგიძლიათ მიჰყვეთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულის და Gradle ქეშები და სხვა დირექტორიები ამოცანებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> საშუალებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.

მიანიჭეთ ამოცანას `id-token: write`, რათა მისი ქეშის ტომები და ქეშირებული checkout მიმაგრდეს მისი დაწყებისთანავე. ამის გარეშე, რანერი ელოდება, სანამ GitHub შეატყობინებს, თუ რომელ ამოცანას ასრულებს, და ამოცანა, რომლის შესახებაც GitHub გვიან ატყობინებს, იწყება ცარიელი ქეშებით. Workflow, რომელიც ავტორიზაციას ახდენს Tuist-ში OpenID Connect-ით, უკვე ანიჭებს მას.

```yaml
permissions:
  contents: read
  id-token: write
```
