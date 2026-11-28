---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions ჯობი Tuist გამშვებებზე: დააკავშირეთ GitHub, მიუთითეთ runs-on Tuist პროფილზე და აკვირდით პროცესს დაფაზე."
}
---
# GitHub Actions {#github-actions}

სამი ცვლილებაა საჭირო, რომ სამუშაო გაეშვას ფლოტზე: დააკავშირეთ GitHub, მიმართეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და შეასრულეთ push.

1. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">დაკავშირებულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` მოვლენებს ამ ორგანიზაციისთვის და ანაწილებს შესაბამის სამუშაოებს ფლოტზე. ამ კავშირის გარეშე, არცერთი სამუშაო ვერ მიაღწევს თქვენს რანერებს.
2. **მიმართეთ `runs-on` Tuist-ის პროფილზე.** ყოველი აქტიური ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

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
   > macOS რანერის იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს პროფილის მიხედვით სამუშაოს დაწყებამდე. თუ გადადიხართ GitHub-ზე განთავსებული რანერებიდან, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და ექშენებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად ეხება Xcode-ის ინსტალაციებს, რომლებიც სპეციფიურია GitHub-ზე განთავსებული იმიჯებისთვის და შეიძლება ჩავარდნენ Tuist Runners-ზე.
   >
   > სხვა Xcode ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს სამუშაო ნაკადში დამატებითი კონფიგურაციის გარეშე.

3. **შეასრულეთ push და დააკვირდით.** სამუშაო ემატება რიგში, იკავებს რანერი და ნაკადი ბრუნდება თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ მიჰყვეთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულების და Gradle-ის ქეშები და სხვა დირექტორიები სამუშაოებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> საშუალებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.

მიანიჭეთ სამუშაოს `id-token: write`, რათა მისი ქეშის ტომები და ქეშირებული checkout მიმაგრდეს დაწყებისთანავე. ამის გარეშე, რანერი ელოდება, სანამ GitHub აცნობებს, თუ რომელ სამუშაოს ასრულებს, და სამუშაო, რომელსაც GitHub გვიან აცნობებს, იწყება ცარიელი ქეშებით. სამუშაო ნაკადი, რომელიც შედის Tuist-ში OpenID Connect-ით, უკვე ანიჭებს ამას.

```yaml
permissions:
  contents: read
  id-token: write
```
