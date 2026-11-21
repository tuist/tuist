---
{
  "title": "Tuist-ის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის ბრძანებების ხაზის ინტერფეისი macOS-ზე ან Linux-ზე mise-ის ან Homebrew-ის გამოყენებით, და დააფიქსირეთ ვერსია გუნდებისა და უწყვეტი ინტეგრაციისთვის."
}
---
# Tuist-ის ინსტალაცია {#install-tuist}

Tuist-ის ბრძანების სტრიქონის ინტერფეისი მუშაობს **macOS**-ზე და **Linux**-ზე და აკავშირებს თქვენს Xcode, გენერირებულ, Gradle, Bazel და Rust პროექტებს Tuist-ის ქეშთან, ინსაიტებთან და გამშვებ ინფრასტრუქტურასთან. მიუხედავად იმისა, რომ შეგიძლიათ ააწყოთ Tuist [წყაროდან](https://github.com/tuist/tuist), ჩვენ გირჩევთ ქვემოთ მოცემული ინსტალაციის მეთოდებიდან ერთ-ერთს, რათა უზრუნველყოთ ვალიდური და დასადასტურებელი ინსტალაცია. Elixir პროექტები იყენებენ `tuist_ex` Hex პაკეტს და არ საჭიროებენ CLI-ს.

## Mise {#recommended-mise}

> [!NOTE]
> თუ Mise არ გაქვთ ინსტალირებული, ჯერ მიჰყევით [დაწყების სახელმძღვანელოს](https://mise.jdx.dev/getting-started.html). Mise არის რეკომენდებული ალტერნატივა [Homebrew](https://brew.sh)-ისთვის, თუ თქვენ ხართ გუნდი ან ორგანიზაცია, რომელსაც სჭირდება ინსტრუმენტების დეტერმინისტული ვერსიების უზრუნველყოფა სხვადასხვა გარემოში.


განსხვავებით ისეთი ინსტრუმენტებისგან, როგორიცაა Homebrew, რომლებიც აინსტალირებენ და ააქტიურებენ ინსტრუმენტის ერთ ვერსიას გლობალურად, **Mise ამაგრებს ვერსიას** ან გლობალურად, ან პროექტის ფარგლებში. გაუშვით `mise use` Tuist-ის ინსტალაციისა და აქტივაციისთვის:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

თუ კლონირებთ პროექტს, რომელსაც უკვე აქვს Tuist-ის ვერსია დამაგრებული `mise.toml`-ში, გაუშვით `mise install` მის ინსტალაციისთვის.

> [!TIP]
> `tuist@latest` გადაიყვანება უახლეს **სტაბილურ** გამოცემაზე. Tuist ასევე აქვეყნებს წინასწარი გამოცემის canary და release candidate ბილდებს; ეს მხოლოდ opt-in რეჟიმშია ხელმისაწვდომი და არასდროს გადაიყვანება `latest`-ით. იხილეთ <.localized_link href="/cli/release/channels">გამოცემის არხები</.localized_link>, რათა გაიგოთ, როგორ დაამაგროთ სანდო სტაბილური ხაზი და როგორ ჩაერთოთ წინასწარ გამოცემებში.

<details>
<summary>Linux-ის მხარდაჭერა</summary>

Linux-ზე Tuist ხელმისაწვდომია მხოლოდ Mise-ის მეშვეობით. ბრძანებები, რომლებიც დამოკიდებულია Xcode-ზე (მაგალითად, `tuist generate`), არ არის ხელმისაწვდომი Linux-ზე, მაგრამ პლატფორმა-დამოუკიდებელი ბრძანებები, როგორიცაა `tuist inspect bundle`, მუშაობს მოსალოდნელად.

</details>


## Homebrew (მხოლოდ macOS) {#recommended-homebrew}

შეგიძლიათ დააინსტალიროთ Tuist [Homebrew](https://brew.sh)-ის და [ჩვენი ფორმულების](https://github.com/tuist/homebrew-tuist) გამოყენებით:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **ბინარული ფაილების ავთენტურობის შემოწმება**
>
> შეგიძლიათ დაადასტუროთ, რომ თქვენი ინსტალაციის ბინარული ფაილები ჩვენ მიერ არის აწყობილი, შემდეგი ბრძანების გაშვებით, რომელიც ამოწმებს, არის თუ არა სერტიფიკატის გუნდი `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://tuist.dev/verify.sh" | bash
> ```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გადამისამართებს გამავალ ტრაფიკს HTTP პროქსის მეშვეობით, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

- მიჰყევით <.localized_link href="/guides/get-started">დაწყების სახელმძღვანელოს</.localized_link>, რათა დააკავშიროთ თქვენი პროექტი Tuist-თან.
- გაეცანით [Tuist-ის ბილდინგის ინფრასტრუქტურას საინჟინრო გუნდებისა და კოდირების აგენტებისთვის](https://tuist.dev) პროდუქტის უფრო ფართო კონტექსტისთვის.
