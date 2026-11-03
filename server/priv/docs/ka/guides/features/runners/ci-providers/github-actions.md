---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · რანერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions დავალება Tuist Runners-ზე: დააკავშირეთ GitHub, მიუთითეთ runs-on Tuist პროფილზე და დააკვირდით შედეგებს დაშბორდზე."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Runners ამჟამად ხელმისაწვდომია მხოლოდ მოწვევით. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ზე](https://slack.tuist.dev), რათა თქვენს ანგარიშზე წვდომა მოგანიჭოთ.

ფლიტზე დავალების გასაშვებად სამი ცვლილებაა საჭირო: დააკავშირეთ GitHub, მიუთითეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და გაუშვით პუში.

1. **მოითხოვეთ წვდომა.** ბეტა პერიოდში Runners ხელმისაწვდომია მხოლოდ მოწვევით. [დაგვიკავშირდით](mailto:contact@tuist.dev) იმ ანგარიშის მითითებით, რომლისთვისაც გსურთ ჩართვა.
2. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` ღონისძიებებს ამ ორგანიზაციისთვის და შესაბამის დავალებებს ფლიტზე აგზავნის. ამ კავშირის გარეშე დავალებები თქვენს runners-ებამდე ვერ მოაღწევს.
3. **მიუთითეთ `runs-on` Tuist-ის პროფილზე.** ყოველი ჩართული ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **აირჩიეთ Xcode runner-ის პროფილით**
   >
   > macOS runner-ის image შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist პროფილის მიხედვით ირჩევს დავალების დაწყებამდე. თუ GitHub-hosted runners-დან გადადიხართ, ამოშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და actions-ებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად ეყრდნობა GitHub-hosted images-ებისთვის სპეციფიკურ Xcode-ის ინსტალაციებს და Tuist Runners-ზე შეიძლება ვერ იმუშაოს.
   >
   > სხვა Xcode ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილში შერჩეულ Xcode-ს workflow-ში დამატებითი კონფიგურაციის გარეშე.

4. **გაუშვით პუში და დააკვირდით.** დავალება რიგში დგება, runner-ი იღებს მას და ნაკადი ბრუნდება თქვენი Tuist dashboard-ის **Runners** სექციაში, სადაც შეგიძლიათ თვალყური ადევნოთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## Cache volumes {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულისა და Gradle-ის cache-ები და სხვა დირექტორიები დავალებებს შორის <.localized_link href="/guides/features/runners/cache-volumes">cache volumes-ის</.localized_link> საშუალებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.

მიანიჭეთ დავალებას `id-token: write`, რათა მისი cache volumes და cached checkout მიმაგრდეს მისი დაწყებისთანავე. ამის გარეშე runner ელოდება, სანამ GitHub აცნობებს, თუ რომელ დავალებას ასრულებს, და GitHub-ის მიერ დაგვიანებით შეტყობინებული დავალება იწყება ცარიელი cache-ებით. Workflow, რომელიც Tuist-ში OpenID Connect-ით შედის, უკვე ანიჭებს ამ უფლებას.

```yaml
permissions:
  contents: read
  id-token: write
```
