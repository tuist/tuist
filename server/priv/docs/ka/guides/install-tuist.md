---
{
  "title": "Tuist-ის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის ბრძანებების ხაზის ინტერფეისი macOS-ზე ან Linux-ზე mise-ის ან Homebrew-ის გამოყენებით და მიამაგრეთ ვერსია გუნდებისა და უწყვეტი ინტეგრაციისთვის."
}
---
# Tuist-ის ინსტალაცია {#install-tuist}

Tuist-ის ბრძანების სტრიქონის ინტერფეისი მუშაობს **macOS**-ზე და **Linux**-ზე და აკავშირებს თქვენს Xcode, გენერირებულ, Gradle და Bazel პროექტებს Tuist-ის ქეშთან, ანალიტიკასთან და გამშვებ ინფრასტრუქტურასთან. მიუხედავად იმისა, რომ Tuist-ის აწყობა შეგიძლიათ [წყაროდან](https://github.com/tuist/tuist), ჩვენ გირჩევთ ქვემოთ მოცემული ინსტალაციის მეთოდებიდან ერთ-ერთს, რათა უზრუნველყოთ ვალიდური და დადასტურებადი ინსტალაცია.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> თუ Mise არ გაქვთ დაინსტალირებული, ჯერ მიჰყევით [დაწყების სახელმძღვანელოს](https://mise.jdx.dev/getting-started.html). Mise არის რეკომენდებული ალტერნატივა [Homebrew](https://brew.sh)-ისთვის, თუ თქვენ ხართ გუნდი ან ორგანიზაცია, რომელსაც სჭირდება ინსტრუმენტების დეტერმინისტული ვერსიების უზრუნველყოფა სხვადასხვა გარემოში.


განსხვავებით ისეთი ინსტრუმენტებისგან, როგორიცაა Homebrew, რომლებიც ინსტალაციას და აქტივაციას ახდენენ ინსტრუმენტის ერთი ვერსიის გლობალურად, **Mise ამაგრებს ვერსიას** ან გლობალურად, ან პროექტის ფარგლებში. გაუშვით `mise use` Tuist-ის ინსტალაციისა და აქტივაციისთვის:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

თუ კლონირებთ პროექტს, რომელსაც უკვე აქვს Tuist-ის ვერსია მიმაგრებული `mise.toml`-ში, გაუშვით `mise install` მისი ინსტალაციისთვის.

> [!TIP]
> `tuist@latest` გადაიხსნება უახლეს **სტაბილურ** რელიზად. Tuist ასევე აქვეყნებს წინარე-რელიზის კანარეულ და რელიზის კანდიდატის აწყობებს; ეს მხოლოდ opt-in რეჟიმშია და არასდროს გადაიხსნება `latest`-ით. იხილეთ <.localized_link href="/cli/release-channels">რელიზის არხები</.localized_link> იმის შესახებ, თუ როგორ მიამაგროთ სანდო სტაბილური ხაზი და როგორ ჩართოთ წინარე-რელიზები.

<details>
<summary>Linux-ის მხარდაჭერა</summary>

Linux-ზე, Tuist ხელმისაწვდომია მხოლოდ Mise-ის მეშვეობით. ბრძანებები, რომლებიც დამოკიდებულია Xcode-ზე (მაგალითად, `tuist generate`), არ არის ხელმისაწვდომი Linux-ზე, მაგრამ პლატფორმისგან დამოუკიდებელი ბრძანებები, როგორიცაა `tuist inspect bundle`, მუშაობს მოსალოდნელად.

</details>


### <a href="https://brew.sh">Homebrew</a> (მხოლოდ macOS) {#recommended-homebrew}

შეგიძლიათ დააინსტალიროთ Tuist [Homebrew](https://brew.sh)-ის და [ჩვენი ფორმულების](https://github.com/tuist/homebrew-tuist) გამოყენებით:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **ბინარული ფაილების ავთენტურობის დადასტურება**
>
> შეგიძლიათ დაადასტუროთ, რომ თქვენი ინსტალაციის ბინარული ფაილები ჩვენ მიერ არის აწყობილი შემდეგი ბრძანების გაშვებით, რომელიც ამოწმებს, არის თუ არა სერტიფიკატის გუნდი `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.
