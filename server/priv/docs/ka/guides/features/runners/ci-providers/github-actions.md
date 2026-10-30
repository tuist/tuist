---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions სამუშაო Tuist გამშვებებზე: დააკავშირეთ GitHub, მიმართეთ runs-on Tuist პროფილს და დააკვირდით პროცესს დაფაზე."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Runners ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენს ანგარიშზე წვდომა მოითხოვოთ.

ფლიტზე სამუშაოს გასაშვებად სამი ცვლილებაა საჭირო: დააკავშირეთ GitHub, მიმართეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და გააკეთეთ push.

1. **მოითხოვეთ წვდომა.** ბეტა პერიოდში Runners მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) იმ ანგარიშით, რომლის გააქტიურებაც გსურთ.
2. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` ღონისძიებებს ამ ორგანიზაციისთვის და შესაბამის სამუშაოებს ფლიტზე აგზავნის. ამ კავშირის გარეშე, არცერთი სამუშაო ვერ მიაღწევს თქვენს runners-ებს.
3. **მიმართეთ `runs-on` Tuist-ის პროფილზე.** ყოველი გააქტიურებული ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

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
   > macOS runner-ის image შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს სამუშაოს დაწყებამდე პროფილის მიხედვით. თუ GitHub-ზე განთავსებული runners-ებიდან გადადიხართ, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და actions-ებს Xcode-ის ვერსიების გადართვისთვის. ეს ნაბიჯები ხშირად ეხმიანება Xcode-ის ინსტალაციებს, რომლებიც სპეციფიკურია GitHub-ზე განთავსებული images-ებისთვის და შეიძლება ვერ იმუშაონ Tuist Runners-ზე.
   >
   > სხვა Xcode ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს workflow-ში დამატებითი კონფიგურაციის გარეშე.

4. **გააკეთეთ push და დააკვირდით.** სამუშაო დგება რიგში, იკავებს ერთ-ერთი runner და ნაკადი ბრუნდება თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ მიჰყვეთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## Cache volumes {#cache-volumes}

შეინახეთ Xcode-ის, მოდულის და Gradle cache-ები და სხვა დირექტორიები სამუშაოებს შორის <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>-ის გამოყენებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.
