---
{
  "title": "Rust-ის პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დაუკავშირეთ თქვენი Rust-ის პროექტი Tuist-ს ბილდებისა და ტესტების, მათ შორის doctests-ის, თვალყურის სადევნებლად და არასტაბილური ტესტების აღმოსაჩენად."
}
---
# Rust-ის პროექტი {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## წინაპირობები

- Cargo-ით აწყობილი Rust-ის პროექტი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-ს პროექტთან. არ გჭირდებათ Rust-ის დამოკიდებულების დამატება ან პროექტის აწყობის პროცესის შეცვლა.

## დააკავშირეთ პროექტი

დააყენეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაშბორდზე, სადაც აწყობის სისტემად მიუთითეთ **Cargo (Rust)**. დაამატეთ `tuist.toml` თქვენი რეპოზიტორიის ფესვში:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

შედით სისტემაში `tuist auth login`-ით, შემდეგ კი ჩვეულებრივი Cargo-ს ბრძანებები გაუშვით Tuist-ის მეშვეობით. CI-ში, `TUIST_TOKEN` მიანიჭეთ პროექტის ტოკენი. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციული ფაილის დამატების ნაცვლად, და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ ისეთივე არგუმენტები, როგორიც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის ფუნქციები (features), ხელსაწყოთა ჯაჭვები (toolchains) და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამომავალ მონაცემებს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ახერხებს ანგარიშის ატვირთვას.

## აგრძელეთ Cargo-ს ბრძანებების გამოყენება

[mise-ის ბრძანებების გარსაცმების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გარსაცმის დამატების შემდეგ გაუშვით `mise reshim`. შემდეგ შეგიძლიათ ჩვეულებრივად გამოიყენოთ `cargo build`, `cargo check` და `cargo test`. Mise მათ თქვენთვის Tuist-ის მეშვეობით ასრულებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდის აგენტებთან მუშაობისას: მათ შეუძლიათ აგრძელონ `cargo build` და `cargo test` გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად ათავსებს ქეშში შესაბამის რეგისტრის ბოლო დონის ბიბლიოთეკებს, ლოკალურად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ხელსაწყოების ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია და ჯერ არ ფარავს ყველა კომპილაციას ან განსხვავებული checkout-ის გზებზე ხელახლა გამოყენებას. მხარდაჭერილი კომპილაციების, ავთენტიკაციის და ხელახლა გამოყენების შემოწმების შესახებ იხილეთ <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link>.

## აწყობის ანალიტიკა

გახსენით **Builds** დაშბორდზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აწყობები და შეადაროთ ლოკალური აწყობები CI-ს. აირჩიეთ აწყობა, რათა იპოვოთ კრეიტები (crates), რომელთა კომპილაციასაც ყველაზე მეტი დრო დასჭირდა, და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება კრეიტებს (crates), არა ცალკეულ საწყის ფაილებს. აწყობის ანგარიშის წაკითხვის შესახებ მეტის გასაგებად იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link>.

## ტესტების ანალიტიკა

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **Tests** დაშბორდზე, რათა ნახოთ წარმატებული, წარუმატებელი და გამოტოვებული ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშდება სუიტების ხანგრძლივობას, მაგრამ სტაბილური libtest არ აჩვენებს თითოეული ტესტის დროს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

მეტის წასაკითხად იხილეთ <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>.
