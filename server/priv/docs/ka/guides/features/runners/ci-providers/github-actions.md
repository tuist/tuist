---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · რანერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions ჯობი Tuist-ის რანერებზე: დააკავშირეთ GitHub, მიუთითეთ runs-on Tuist-ის პროფილზე და დააკვირდით შედეგს დაშბორდში."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **მხოლოდ GitHub-ის ორგანიზაციებისთვის**
>
> Tuist Runners ასრულებს სამუშაოებს მხოლოდ იმ რეპოზიტორიებიდან, რომლებიც ეკუთვნის GitHub-ის ორგანიზაციას და არა პირად ანგარიშს.

ფლოტზე სამუშაოს გაშვება სამ ცვლილებას მოითხოვს: დააკავშირეთ GitHub, მიუთითეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და განახორციელეთ push.

1. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub-ის ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` მოვლენებს ამ ორგანიზაციისთვის და შესაბამის სამუშაოებს ფლოტზე აგზავნის. ამ კავშირის გარეშე, ვერცერთი სამუშაო ვერ მიაღწევს თქვენს გამშვებებს (runners).
2. **მიუთითეთ `runs-on` Tuist-ის პროფილზე.** ყოველი აქტიური ანგარიში იწყება ორი გამოყენებისთვის მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **აირჩიეთ Xcode გამშვების პროფილით**
   >
   > macOS გამშვების (runner) იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს სამუშაოს დაწყებამდე პროფილის მიხედვით. თუ გადადიხართ GitHub-ზე განთავსებული გამშვებიდან, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და მოქმედებებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად ეხება Xcode-ის ინსტალაციებს, რომლებიც სპეციფიურია GitHub-ზე განთავსებული იმიჯებისთვის და შეიძლება ვერ იმუშაონ Tuist Runners-ზე.
   >
   > სხვა Xcode ვერსიის გამოსაყენებლად, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს workflow-ში დამატებითი კონფიგურაციის გარეშე.

3. **განახორციელეთ push და დააკვირდით.** სამუშაო რიგში დგება, გამშვები (runner) იღებს მას და ნაკადი ბრუნდება თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ თვალყური ადევნოთ ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულის და Gradle ქეშები და სხვა დირექტორიები სამუშაოებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> გამოყენებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.

მიანიჭეთ სამუშაოს `id-token: write`, რათა მისი ქეშის ტომები და ქეშირებული checkout მიმაგრდეს მისი დაწყებისთანავე. ამის გარეშე, გამშვები (runner) ელოდება, სანამ GitHub შეატყობინებს, თუ რომელ სამუშაოს ასრულებს, და GitHub-ის მიერ გვიან შეტყობინებული სამუშაო ცარიელი ქეშებით იწყება. Workflow, რომელიც Tuist-ში OpenID Connect-ით შედის, უკვე ანიჭებს ამ უფლებას.

```yaml
permissions:
  contents: read
  id-token: write
```
