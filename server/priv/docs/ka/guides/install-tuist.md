---
{
  "title": "Tuist-ის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის ბრძანების ხაზის ინტერფეისი macOS-ზე ან Linux-ზე mise-ის ან Homebrew-ის გამოყენებით და მიამაგრეთ ვერსია გუნდებისა და უწყვეტი ინტეგრაციისთვის."
}
---
# Tuist-ის ინსტალაცია {#install-tuist}

Tuist-ის ბრძანების სტრიქონის ინტერფეისი მუშაობს **macOS**-ზე და **Linux**-ზე და აკავშირებს თქვენს Xcode, გენერირებულ, Gradle, Bazel და Rust პროექტებს Tuist-ის ქეშთან, ანალიტიკასთან და გამშვებ ინფრასტრუქტურასთან. მიუხედავად იმისა, რომ Tuist-ის აწყობა [წყაროდან](https://github.com/tuist/tuist) შეგიძლიათ, ჩვენ გირჩევთ ქვემოთ მოცემული ინსტალაციის მეთოდებიდან ერთ-ერთს, რათა უზრუნველყოთ ვალიდური და ვერიფიცირებადი ინსტალაცია. Elixir პროექტები იყენებენ `tuist_ex` Hex პაკეტს და არ საჭიროებენ CLI-ს.

## Mise {#recommended-mise}

> [!NOTE]
> თუ Mise დაინსტალირებული არ გაქვთ, ჯერ მიჰყევით [დაწყების სახელმძღვანელოს](https://mise.jdx.dev/getting-started.html). Mise არის [Homebrew](https://brew.sh)-ის რეკომენდებული ალტერნატივა, თუ თქვენ ხართ გუნდი ან ორგანიზაცია, რომელსაც სჭირდება ინსტრუმენტების დეტერმინისტული ვერსიების უზრუნველყოფა სხვადასხვა გარემოში.


განსხვავებით ისეთი ინსტრუმენტებისგან, როგორიცაა Homebrew, რომელიც აინსტალირებს და ააქტიურებს ინსტრუმენტის ერთ ვერსიას გლობალურად, **Mise ამაგრებს ვერსიას** ან გლობალურად, ან პროექტის ფარგლებში. გაუშვით `mise use`, რათა დააინსტალიროთ და გაააქტიუროთ Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

თუ კლონირებთ პროექტს, რომელსაც უკვე აქვს Tuist-ის ვერსია მიბმული `mise.toml`-ში, გაუშვით `mise install`, რათა დააინსტალიროთ ის.

> [!TIP]
> `tuist@latest` გადაიხედება უახლეს **სტაბილურ** რელიზად. Tuist ასევე აქვეყნებს წინარელიზის canary და release candidate ბილდებს; ისინი მხოლოდ opt-in რეჟიმშია და არასდროს გადაიხედება `latest`-ით. იხილეთ <.localized_link href="/cli/release/channels">გამოშვების არხები</.localized_link>, რათა გაიგოთ, როგორ მიებათ სტაბილური ხაზი, რომლის სანდოობაც შეგიძლიათ და როგორ ჩაერთოთ წინარელიზებში.

<details>
<summary>Linux-ის მხარდაჭერა</summary>

Linux-ზე Tuist ხელმისაწვდომია მხოლოდ Mise-ის საშუალებით. ბრძანებები, რომლებიც დამოკიდებულია Xcode-ზე (მაგალითად, `tuist generate`), Linux-ზე ხელმისაწვდომი არ არის, მაგრამ პლატფორმა-დამოუკიდებელი ბრძანებები, როგორიცაა `tuist inspect bundle`, მოსალოდნელად მუშაობს.

</details>


## Homebrew (მხოლოდ macOS) {#recommended-homebrew}

შეგიძლიათ დააინსტალიროთ Tuist [Homebrew](https://brew.sh)-ის და [ჩვენი ფორმულების](https://github.com/tuist/homebrew-tuist) გამოყენებით:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **ბინარული ფაილების ავთენტურობის ვერიფიკაცია**
>
> შეგიძლიათ დაადასტუროთ, რომ თქვენი ინსტალაციის ბინარული ფაილები ჩვენ მიერ არის აწყობილი შემდეგი ბრძანების გაშვებით, რომელიც ამოწმებს, არის თუ არა სერთიფიკატის გუნდი `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.
