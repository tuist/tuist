---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **მხოლოდ მიწვევით**
>
> Tuist Runners ამჟამად მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენს ანგარიშზე წვდომა მოითხოვოთ.

Tuist აკვირდება თქვენს Buildkite კლასტერში განთავსებულ თვითმასპინძელ რიგებს და ასრულებს იქ ნაპოვნ დავალებებს ფლოტზე. თქვენი პაიპლაინები Buildkite-ზე გრძელდება; იცვლება მხოლოდ გამოთვლითი რესურსები. ფლოტზე დავალების გასაშვებად სამი ცვლილებაა საჭირო: შეაერთეთ თქვენი კლასტერი, მიანიჭეთ რიგს Tuist <.localized_link href="/guides/features/runners/profiles">პროფილის</.localized_link> სახელი და მიმართეთ ის ნაბიჯიდან.

1. **მოითხოვეთ წვდომა.** ბეტა პერიოდში Runners მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) იმ ანგარიშით, რომლის გააქტიურებაც გსურთ.
2. **შეაერთეთ თქვენი კლასტერი.** Buildkite-ში გახსენით თქვენი კლასტერი, გადადით **Agent Tokens**-ზე და შექმენით ტოკენი; ის იწყება `bkct_`-ით. თქვენს Tuist დაშბორდზე გადადით **Settings → Integrations**-ზე, აირჩიეთ **Connect** Buildkite ბარათზე და შეიყვანეთ თქვენი ორგანიზაციის slug და ტოკენი. ტოკენი ინახება დაშიფრული და აღარასდროს ჩანს. ორგანიზაციის შესაცვლელად ან ტოკენის განახლებისთვის მოგვიანებით, შეცვალეთ ველები ბარათზე და აირჩიეთ **Save changes**. Tuist ერთი წუთის განმავლობაში დაიწყებს კლასტერზე დაკვირვებას.
3. **მიანიჭეთ რიგს Tuist პროფილის სახელი.** ყოველი გააქტიურებული ანგარიში იწყება ორი გამოსაყენებლად მზა <.localized_link href="/guides/features/runners/profiles">პროფილით</.localized_link>, `linux` და `macos`, და დავალება აღიქმება, როცა მისი რიგის გასაღები ემთხვევა პროფილის ლეიბლს. შექმენით თვითმასპინძელი რიგები თქვენს კლასტერში გასაღებებით `tuist-linux` და `tuist-macos`, შემდეგ მიმართეთ ერთ-ერთს ნაბიჯიდან:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **გაუშვით და დააკვირდით.** დავალება რიგში დგება, runner-ის მიერ აღიქმება და გადაიცემა უკან თქვენი Tuist დაშბორდის **Runners** სექციაში, სადაც შეგიძლიათ თვალყური ადევნოთ მის ლოგებს, ნაბიჯებს და მანქანის მეტრიკებს. runner აგზავნის ლოგს დავალების შიგნიდან იმ დავალებისთვის შეზღუდული კრედენციალით, ამიტომ Buildkite API ტოკენი არ არის საჭირო.

## შეჩერება და გათიშვა {#pausing-and-disconnecting}

Buildkite რიგზე გაგზავნის შეჩერება აჩერებს Tuist-ს ახალი დავალებების აღებაში. უკვე გაშვებული დავალებები არ იცვლება.

კლასტერის გათიშვა Buildkite ბარათზე **Settings → Integrations**-ის ქვეშ სრულად აჩერებს Tuist-ის მიერ მასზე დაკვირვებას.

## ქეშის ტომები {#cache-volumes}

შეინარჩუნეთ Xcode, მოდულის და Gradle ქეშები და სხვა დირექტორიები დავალებებს შორის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების</.localized_link> გამოყენებით. დაამატეთ ისინი checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც მათ იყენებენ.
