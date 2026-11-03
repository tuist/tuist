---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI პროვაიდერები · რანერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით თქვენი პირველი GitHub Actions ჯობი Tuist რანერებზე: დააკავშირეთ GitHub, მიმართეთ runs-on Tuist პროფილზე და აკვირდით მას დაშბორდზე."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **მხოლოდ მიწვევით**
>
> Tuist Runners ამჟამად მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენი ანგარიშისთვის წვდომა მოითხოვოთ.

ფლიტზე სამუშაოს გასაშვებად საჭიროა სამი ცვლილება: დააკავშირეთ GitHub, მიუთითეთ `runs-on` Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და გააკეთეთ push.

1. **მოითხოვეთ წვდომა.** ბეტა პერიოდში Runners მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) იმ ანგარიშით, რომლის ჩართვაც გსურთ.
2. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` ღონისძიებებს ამ ორგანიზაციისთვის და შესაბამის სამუშაოებს ფლიტზე აგზავნის. ამ კავშირის გარეშე, სამუშაოები თქვენს რანერებამდე ვერ მიაღწევს.
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
   > **Xcode-ის არჩევა რანერის პროფილით**
   >
   > macOS რანერის იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist პროფილის მიხედვით ირჩევს სამუშაოს დაწყებამდე. თუ GitHub-ზე განთავსებული რანერებიდან გადადიხართ, ამოიღეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და ქმედებებს Xcode-ის ვერსიების გადართვისთვის. ეს ნაბიჯები ხშირად ეხება Xcode-ის ინსტალაციებს, რომლებიც სპეციფიურია GitHub-ზე განთავსებული იმიჯებისთვის და შეიძლება ვერ იმუშაონ Tuist Runners-ზე.
   >
   > Xcode-ის სხვა ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს სამუშაო ნაკადში დამატებითი კონფიგურაციის გარეშე.

4. **გააკეთეთ push და დააკვირდით.** სამუშაო დგება რიგში, რანერი იღებს მას და ნაკადი ბრუნდება თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ თვალყური ადევნოთ ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულისა და Gradle-ის ქეშები და სხვა დირექტორიები სამუშაოებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> საშუალებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.
