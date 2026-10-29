---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist-ის ინსტალაცია {#install-tuist}

Tuist-ის ბრძანების სტრიქონის ინტერფეისი მუშაობს **macOS**-ზე და **Linux**-ზე და აკავშირებს თქვენს Xcode, გენერირებულ, Gradle და Bazel პროექტებს Tuist-ის ქეშთან, ანალიტიკასთან და გამშვებ ინფრასტრუქტურასთან. მიუხედავად იმისა, რომ შეგიძლიათ ააწყოთ Tuist [წყაროდან](https://github.com/tuist/tuist), ჩვენ გირჩევთ ქვემოთ მოცემული ინსტალაციის მეთოდებიდან ერთ-ერთს, რათა უზრუნველყოთ ვალიდური და დასადასტურებელი ინსტალაცია.

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> თუ Mise არ გაქვთ დაინსტალირებული, ჯერ მიჰყევით [დაწყების სახელმძღვანელოს](https://mise.jdx.dev/getting-started.html). Mise არის რეკომენდებული ალტერნატივა [Homebrew](https://brew.sh)-ისთვის, თუ ხართ გუნდი ან ორგანიზაცია, რომელსაც სჭირდება ინსტრუმენტების დეტერმინისტული ვერსიების უზრუნველყოფა სხვადასხვა გარემოში.


Homebrew-ის მსგავსი ინსტრუმენტებისგან განსხვავებით, რომლებიც აინსტალირებენ და ააქტიურებენ ინსტრუმენტის ერთ ვერსიას გლობალურად, **Mise ამაგრებს ვერსიას** ან გლობალურად, ან პროექტის ფარგლებში. გაუშვით `mise use`, რათა დააინსტალიროთ და გაააქტიუროთ Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

თუ კლონირებთ პროექტს, რომელსაც უკვე აქვს Tuist-ის ვერსია მიმაგრებული `mise.toml`-ში, გაუშვით `mise install`, რათა დააინსტალიროთ ის.

> [!TIP]
> `tuist@latest` გადაიხედება უახლეს **სტაბილურ** გამოშვებაზე. Tuist ასევე აქვეყნებს წინასწარი გამოშვების canary და release candidate აწყობებს; ისინი მხოლოდ opt-in რეჟიმშია ხელმისაწვდომი და არასდროს გადაიხედება `latest`-ით. იხილეთ <.localized_link href="/cli/release-channels">გამოშვების არხები</.localized_link>, რათა გაიგოთ, როგორ მიამაგროთ სანდო სტაბილური ხაზი და როგორ ჩაერთოთ წინასწარ გამოშვებებში.

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
> შეგიძლიათ დაადასტუროთ, რომ თქვენი ინსტალაციის ბინარული ფაილები ჩვენ მიერ არის აწყობილი, შემდეგი ბრძანების გაშვებით, რომელიც ამოწმებს, არის თუ არა სერთიფიკატის გუნდი `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.
