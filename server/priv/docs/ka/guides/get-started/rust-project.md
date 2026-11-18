---
{
  "title": "Rust-ის პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დააკავშირეთ თქვენი Rust-ის პროექტი Tuist-თან, რათა თვალი ადევნოთ ბილდებსა და ტესტებს (მათ შორის doctests-ს) და აღმოაჩინოთ არასტაბილური ტესტები."
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

- Rust-პროექტი, აგებული Cargo-თი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-პროექტთან. არ გჭირდებათ Rust-დამოკიდებულების დამატება ან პროექტის აგების წესის შეცვლა.

## დააკავშირეთ პროექტი

დააინსტალირეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაფაზე, სადაც აგების სისტემად მითითებული იქნება **Cargo (Rust)**. შემდეგ დაამატეთ პროექტი სამუშაო სივრცის ძირეულ `Cargo.toml`-ში:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo უგულებელყოფს `metadata` ცხრილებს, ამიტომ ეს არ ცვლის პროექტის აგების წესს. ერთი კრეიტისთვის, რომელსაც არ აქვს `[workspace]` ცხრილი, გამოიყენეთ `[package.metadata.tuist]`. ცხრილი იღებს იმავე პარამეტრებს, რასაც `tuist.toml` ფაილი, რომლის გამოყენებაც შეგიძლიათ მაგალითად მაშინ, როცა რეპოზიტორიაში სხვა სააგებო სისტემების პროექტებიცაა. ორივეს არსებობისას უპირატესობა ენიჭება `tuist.toml`-ს.

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით ჩვეულებრივი Cargo-ბრძანებები Tuist-ის მეშვეობით. CI-ში გაიარეთ ავთენტიკაცია თქვენი CI-მოწყობილობის OIDC-იდენტობით ან დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რასაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის ფუნქციები, ინსტრუმენტების ჯაჭვები და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამონატანს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## აგრძელეთ Cargo-ს ბეჭდვა

[mise-ის ბრძანების გარსების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გარსის დამატების შემდეგ გაუშვით `mise reshim`. შემდეგ შეგიძლიათ ჩვეულებრივად გამოიყენოთ `cargo build`, `cargo check` და `cargo test`. Mise მათ თქვენთვის Tuist-ის მეშვეობით ასრულებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდის აგენტებთან მუშაობისას: მათ შეუძლიათ აგრძელონ `cargo build` და `cargo test`-ის გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად ათავსებს ქეშში შესაბამის კომპილაციებს, დამოკიდებულებებს და აგების სკრიპტების გაშვებებს, ადგილობრივად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ინსტრუმენტის ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია, ვალიდირებულია Apple silicon Mac-ებზე და ჯერ არ მოიცავს ყველა კომპილაციას. მხარდაჭერილი კომპილაციების, ავთენტიკაციის და ხელახლა გამოყენების შემოწმების შესახებ იხილეთ <.localized_link href="/guides/features/cache/rust">Rust ქეში</.localized_link>.

## აგების ინსაიტები

გახსენით **Builds** დაფარდაზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ადგილობრივი აგებები CI-ს. აირჩიეთ აგება, რათა იპოვოთ კრეიტები, რომელთა კომპილაციასაც ყველაზე მეტი დრო დასჭირდა და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის ნიშნები ეხება კრეიტებს, არა ცალკეულ საწყის ფაილებს. აგების ანგარიშის წაკითხვის შესახებ მეტის გასაგებად იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link>.

## ტესტების ინსაიტები

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **Tests** დაფარდაზე, რათა ნახოთ წარმატებული, ჩავარდნილი და იგნორირებული ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშდება სუიტების ხანგრძლივობას, მაგრამ სტაბილური libtest არ აჩვენებს თითოეული ტესტის დროს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

მეტის წაკითხვა <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>-ში და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>-ში.

## სავაჭრო ნიშნები {#trademarks}

Rust და Cargo არის Rust Foundation-ის სავაჭრო ნიშნები. Tuist არ არის დაკავშირებული ან ნაჩვენები Rust Project-ის ან Rust Foundation-ის მიერ. ამ სახელმძღვანელოებში Rust-ის ლოგო არის © Rust Foundation, გამოყენებულია [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ლიცენზიით და ნაჩვენებია ერთ ფერში, რომელიც ემთხვევა გვერდის თემას.
