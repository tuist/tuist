---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · რანერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions დავალება Tuist Runners-ზე: დააკავშირეთ GitHub, მიმართეთ runs-on Tuist პროფილზე და დააკვირდით მას დაშბორდზე."
}
---
# GitHub Actions {#github-actions}

<!-- @snippet: ./_invite-only -->

Fleet-ზე დავალების გასაშვებად სამი ცვლილებაა საჭირო: GitHub-ის დაკავშირება, `runs-on`-ის მითითება Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და პუში.

1. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">დაკავშირებულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` მოვლენებს ამ ორგანიზაციისთვის და ანაწილებს შესაბამის დავალებებს fleet-ზე. ამ კავშირის გარეშე, დავალებები თქვენს რანერებამდე ვერ მივა.
2. **მიმართეთ `runs-on` Tuist-ის პროფილს.** ყოველი აქტიური ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

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
   > macOS რანერის იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს დავალების დაწყებამდე პროფილის მიხედვით. თუ გადადიხართ GitHub-ის მიერ ჰოსტინგულ რანერებზე, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და ექშენებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად მიმართავენ GitHub-ის მიერ ჰოსტინგული იმიჯებისთვის დამახასიათებელ Xcode-ის ინსტალაციებს და შეიძლება ჩავარდნენ Tuist Runners-ზე.
   >
   > Xcode-ის სხვა ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილით არჩეულ Xcode-ს workflow-ში დამატებითი კონფიგურაციის გარეშე.

3. **გაუშვით პუში და დააკვირდით.** დავალება დგება რიგში, იკავებს რანერი და სტრიმდება უკან თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ მიადევნოთ თვალი მის ლოგებს, ნაბიჯებსა და მანქანის მეტრიკებს.

## Cache volumes {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულისა და Gradle-ის ქეშები და სხვა დირექტორიები დავალებებს შორის <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>-ის გამოყენებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.

მიანიჭეთ დავალებას `id-token: write`, რათა მისმა cache volumes-მა და ქეშირებულმა checkout-მა მიმაგრება დაიწყოს დაწყებისთანავე. ამის გარეშე, რანერი ელოდება, სანამ GitHub აცნობებს, თუ რომელ დავალებას ასრულებს, და GitHub-ის მიერ დაგვიანებით ნაჩვენები დავალება იწყება ცარიელი ქეშებით. Workflow, რომელიც შედის Tuist-ში OpenID Connect-ით, უკვე ანიჭებს ამ უფლებას.

```yaml
permissions:
  contents: read
  id-token: write
```
