---
{
  "title": "Rust-ის პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დააკავშირეთ თქვენი Rust-ის პროექტი Tuist-თან ბილდებისა და ტესტების, მათ შორის doctests-ის, თვალყურის სადევნებლად და არასტაბილური ტესტების აღმოჩენისთვის."
}
---
# Rust-პროექტი {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## წინაპირობები

- Cargo-ით აგებული Rust-პროექტი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-პროექტთან. არ არის საჭირო Rust-დამოკიდებულების დამატება ან პროექტის აგების გზის შეცვლა.

## პროექტის მიერთება

დააინსტალირეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაფაზე, სადაც აგების სისტემად მითითებული იქნება **Cargo (Rust)**. შემდეგ დაამატეთ პროექტი სამუშაო სივრცის ფესვის `Cargo.toml`-ში:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo უგულებელყოფს `metadata` ცხრილებს, ამიტომ ეს არ ცვლის თქვენი პროექტის აგების გზას. ერთი კრეიტისთვის, რომელსაც არ აქვს `[workspace]` ცხრილი, გამოიყენეთ `[package.metadata.tuist]`. ცხრილი იღებს იმავე პარამეტრებს, რასაც `tuist.toml` ფაილი, რომელიც ასევე შეგიძლიათ გამოიყენოთ, მაგალითად, როცა რეპოზიტორიაში სხვა აგების სისტემების პროექტებიცაა. როცა ორივე არსებობს, `tuist.toml` აქვს უპირატესობა.

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით ჩვეულებრივი Cargo-ბრძანებები Tuist-ის მეშვეობით. CI-ში გაიარეთ ავტორიზაცია თქვენი CI-მოწოდებლის OIDC-იდენტობით ან დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რასაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის ფუნქციები, ინსტრუმენტების ჯაჭვები და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამოსავალს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## განაგრძეთ Cargo-ს ბრძანებების შეყვანა

[mise-ის ბრძანების შემფუთავების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

შემფუთავის დამატების შემდეგ გაუშვით `mise reshim`. შემდეგ შეგიძლიათ ჩვეულებრივად გამოიყენოთ `cargo build`, `cargo check` და `cargo test`. Mise მათ თქვენთვის Tuist-ის მეშვეობით ასრულებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდირების აგენტებთან მუშაობისას: მათ შეუძლიათ განაგრძონ `cargo build` და `cargo test` გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად აქეშებს შესაბამის კომპილაციებს, დამოკიდებულებებს და აგების სკრიპტების გაშვებებს, ლოკალურად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ინსტრუმენტის ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია, ვალიდირებულია Apple silicon Mac-ებზე და ჯერ არ ფარავს ყველა კომპილაციას. მხარდაჭერილი კომპილაციების, ავტორიზაციის და ხელახლა გამოყენების შემოწმების შესახებ იხილეთ <.localized_link href="/guides/features/cache/rust">Rust-ქეში</.localized_link>.

## აგების ინფორმაცია

გახსენით **აგებები** დაფარდაზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ლოკალური აგებები CI-ს. აირჩიეთ აგება, რათა იპოვოთ კრეიტები, რომელთა კომპილაციასაც ყველაზე მეტი დრო დასჭირდა და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება კრეიტებს, არა ცალკეულ საწყის ფაილებს. აგების ანგარიშის წაკითხვის შესახებ მეტის სანახავად იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust-ის აგების ინფორმაცია</.localized_link>.

## ტესტების ინფორმაცია

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **ტესტები** დაფარდაზე, რათა ნახოთ წარმატებული, წარუმატებელი და იგნორირებული ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშობს სუიტების ხანგრძლივობას, მაგრამ სტაბილური libtest არ აჩვენებს ცალკეული ტესტების დროს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

მეტის წასაკითხად იხილეთ <.localized_link href="/guides/features/test-insights/rust">Rust-ის ტესტების ინფორმაცია</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust-ის არასტაბილური ტესტები</.localized_link>.

## სავაჭრო ნიშნები {#trademarks}

Rust და Cargo არის Rust Foundation-ის სავაჭრო ნიშნები. Tuist არ არის დაკავშირებული ან მხარდაჭერილი Rust Project-ის ან Rust Foundation-ის მიერ. Rust-ის ლოგო ამ სახელმძღვანელოებში არის © Rust Foundation, გამოყენებულია [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ლიცენზიით და ნაჩვენებია ერთ ფერში, რომელიც ემთხვევა გვერდის თემას.
