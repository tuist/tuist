---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first GitHub Actions job on Tuist Runners: connect GitHub, point runs-on at a Tuist profile, and watch it in the dashboard."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Runners ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ზე](https://slack.tuist.dev), რათა მიიღოთ წვდომა თქვენს ანგარიშზე.

ფლიტზე სამუშაოს გაშვება სამ ცვლილებას მოითხოვს: GitHub-თან დაკავშირება, `runs-on`-ის მიმართვა Tuist-ის <.localized_link href="/guides/features/runners/profiles">პროფილზე</.localized_link> და push-ის შესრულება.

1. **მოითხოვეთ წვდომა.** ბეტა პერიოდში Runners მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) იმ ანგარიშის მითითებით, რომლის აქტივაციაც გსურთ.
2. **დააკავშირეთ GitHub.** დარწმუნდით, რომ თქვენი პროექტი <.localized_link href="/guides/integrations/gitforge/github">მიბმულია თქვენს GitHub ორგანიზაციასთან</.localized_link>. Tuist იღებს `workflow_job` ღონისძიებებს ამ ორგანიზაციისთვის და ფლიტზე გადამისამართებს შესაბამის სამუშაოებს. ამ კავშირის გარეშე, სამუშაოები თქვენს Runners-ს ვერ მიაღწევს.
3. **მიმართეთ `runs-on` Tuist-ის პროფილს.** ყოველი აქტიური ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>: `linux` და `macos`. მიმართეთ მათ `tuist-` პრეფიქსით:

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
   > macOS რანერის იმიჯი შეიცავს Xcode-ის ერთ ვერსიას, რომელსაც Tuist ირჩევს პროფილის მიხედვით სამუშაოს დაწყებამდე. თუ გადადიხართ GitHub-ზე განთავსებული რანერებიდან, წაშალეთ ნაბიჯები, რომლებიც იყენებენ `xcode-select --switch` (ან `xcode-select -s`) ან სხვა ინსტრუმენტებსა და ქმედებებს Xcode-ის ვერსიების გადასართავად. ეს ნაბიჯები ხშირად ეყრდნობა Xcode-ის ინსტალაციებს, რომლებიც სპეციფიკურია GitHub-ზე განთავსებული იმიჯებისთვის და შეიძლება ჩავარდნენ Tuist Runners-ზე.
   >
   > სხვა Xcode ვერსიის გამოყენებისთვის, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">შექმენით ან აირჩიეთ პროფილი</.localized_link> ამ ვერსიით და განაახლეთ `runs-on`, მაგალითად `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun`, და `swift` შემდეგ გამოიყენებენ პროფილით შერჩეულ Xcode-ს დამატებითი კონფიგურაციის გარეშე სამუშაო ნაკადში.

4. **გააკეთეთ push და დააკვირდით.** სამუშაო დგება რიგში, იღებს რანერი და ნაკადი უბრუნდება თქვენი Tuist დაშბორდის **Runners** სექციას, სადაც შეგიძლიათ თვალყური ადევნოთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode-ის, მოდულის და Gradle-ის ქეშები და სხვა დირექტორიები სამუშაოებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> გამოყენებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.
