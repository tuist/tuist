---
{
  "title": "Tuist-ის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის ბრძანების ხაზის ინტერფეისი macOS-ზე ან Linux-ზე mise-ის ან Homebrew-ის გამოყენებით და მიამაგრეთ ვერსია გუნდებისა და უწყვეტი ინტეგრაციისთვის."
}
---
# Tuist-ის ინსტალაცია {#install-tuist}

Tuist-ის ბრძანების ხაზის ინტერფეისი მუშაობს **macOS**-ზე და **Linux**-ზე და აკავშირებს თქვენს Xcode, გენერირებულ, Gradle, Bazel და Rust პროექტებს Tuist-ის ქეშთან, ანალიტიკასთან და გამშვებ ინფრასტრუქტურასთან. მიუხედავად იმისა, რომ შეგიძლიათ ააწყოთ Tuist [წყარო კოდიდან](https://github.com/tuist/tuist), ჩვენ გირჩევთ ქვემოთ მოცემული ინსტალაციის მეთოდებიდან ერთ-ერთს, რათა უზრუნველყოთ ვალიდური და შემოწმებადი ინსტალაცია. Elixir პროექტები იყენებენ `tuist_ex` Hex პაკეტს და არ საჭიროებენ CLI-ს.

## Mise {#recommended-mise}

> [!NOTE]
> თუ Mise დაინსტალირებული არ გაქვთ, ჯერ გაეცანით [დაწყების სახელმძღვანელოს](https://mise.jdx.dev/getting-started.html). Mise არის რეკომენდებული ალტერნატივა [Homebrew](https://brew.sh)-ისთვის, თუ თქვენ ხართ გუნდი ან ორგანიზაცია, რომელსაც სჭირდება ინსტრუმენტების დეტერმინისტული ვერსიების უზრუნველყოფა სხვადასხვა გარემოში.


განსხვავებით ისეთი ინსტრუმენტებისგან, როგორიცაა Homebrew, რომლებიც ინსტალაციას და აქტივაციას ახდენენ ინსტრუმენტის ერთი ვერსიის გლობალურად, **Mise ამაგრებს ვერსიას** ან გლობალურად, ან პროექტის ფარგლებში. გაუშვით `mise use` Tuist-ის ინსტალაციისა და აქტივაციისთვის:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

თუ დააკლონებთ პროექტს, რომელსაც უკვე აქვს Tuist-ის ვერსია მიმაგრებული `mise.toml`-ში, გაუშვით `mise install` მის ინსტალაციისთვის.

> [!TIP]
> `tuist@latest` გადაიხედება უახლეს **სტაბილურ** გამოცემამდე. Tuist ასევე აქვეყნებს წინასწარი გამოცემის კანარის და რელიზ კანდიდატის ბილდებს; ისინი მხოლოდ ნებაყოფლობითია და არასდროს გადაიხედება `latest`-ით. იხილეთ <.localized_link href="/cli/release/channels">გამოცემის არხები</.localized_link> სანდო სტაბილური ხაზის მიმაგრებისა და წინასწარ გამოცემებზე ჩართვის შესახებ.

<details>
<summary>Linux-ის მხარდაჭერა</summary>

Linux-ზე, Tuist ხელმისაწვდომია მხოლოდ Mise-ის მეშვეობით. ბრძანებები, რომლებიც დამოკიდებულია Xcode-ზე (მაგალითად, `tuist generate`), არ არის ხელმისაწვდომი Linux-ზე, მაგრამ პლატფორმა-დამოუკიდებელი ბრძანებები, როგორიცაა `tuist inspect bundle`, მუშაობს მოსალოდნელად.

</details>


## Homebrew (მხოლოდ macOS) {#recommended-homebrew}

შეგიძლიათ დააინსტალიროთ Tuist [Homebrew](https://brew.sh)-ისა და [ჩვენი ფორმულების](https://github.com/tuist/homebrew-tuist) გამოყენებით:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **ბინარული ფაილების ავთენტურობის შემოწმება**
>
> შეგიძლიათ შეამოწმოთ, რომ თქვენი ინსტალაციის ბინარული ფაილები ჩვენ მიერ არის აწყობილი, შემდეგი ბრძანების გაშვებით, რომელიც ამოწმებს, არის თუ არა სერტიფიკატის გუნდი `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://tuist.dev/verify.sh" | bash
> ```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს ატარებს HTTP პროქსის მეშვეობით, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

- მიჰყევით <.localized_link href="/guides/get-started">დაწყების სახელმძღვანელოს</.localized_link> თქვენი პროექტის Tuist-თან დასაკავშირებლად.
- გაეცანით [Tuist-ის ბილდ ინფრასტრუქტურას საინჟინრო გუნდებისა და კოდირების აგენტებისთვის](https://tuist.dev) პროდუქტის უფრო ფართო კონტექსტისთვის.
